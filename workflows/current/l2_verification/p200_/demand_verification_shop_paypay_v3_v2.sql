--8/10,11の九州地方大雨と8/21,22の台風の影響を考慮した（同日を除外した）ver.
with shop_list as (
  select distinct
    property_id
    , segment
    , td_time_parse(before_from, 'jst') as before_from
    , td_time_parse(before_to, 'jst') as before_to
    , td_time_parse(after_from, 'jst') as after_from
    , least(td_time_parse(after_to, 'jst'), ${moment(session_date).subtract(1, 'day').unix()}) as after_to
  from
    ${td.database}.list_demand_paypay_v3
    left join (select shop_no, property_id from l2_integration_datamart.shop_info) using (shop_no)
)
, prep_orders as (
  select
    segment
    , case
        when td_time_parse(business_date, 'jst') between before_from and before_to
          then '実施前:'||td_time_format(before_from, 'MMdd', 'jst')||'~'||td_time_format(before_to, 'MMdd', 'jst')
        when td_time_parse(business_date, 'jst') between after_from and after_to
          then '実施中:'||td_time_format(after_from, 'MMdd', 'jst')||'~'||td_time_format(after_to, 'MMdd', 'jst')
      end as span
    , if(dow(cast(business_date as date)) in (6, 7) or coalesce(hldy, 0) = 1, '土日祝', '平日') as dow_type
    , count(distinct if(treatment_minutes>0, order_id)) as order_count
    , count(distinct if(treatment_minutes>0 and is_repeat = 0, order_id)) as order_count_new
    , sum(if(order_detail_id_seq = 1, treatment_minutes_in_hour)) as treatment_minutes
    , sum(if(order_id_hour_seq = 1, uriage1)) as sales_amount
  from
    _integration_datamart.cls_order_detail
    inner join shop_list using (property_id)
    left join (select substr(target_date, 1, 10) as business_date, 1 as hldy from _l1_mysql_pos.mst_holidays) using (business_date)
  where
    business_date not in ('2025-08-10', '2025-08-11', '2025-08-21', '2025-08-22')
  group by
    1,2,3
)
, cls_sufficiency as (
  select
    segment
    , case
        when td_time_parse(business_date, 'jst') between before_from and before_to
          then '実施前:'||td_time_format(before_from, 'MMdd', 'jst')||'~'||td_time_format(before_to, 'MMdd', 'jst')
        when td_time_parse(business_date, 'jst') between after_from and after_to
          then '実施中:'||td_time_format(after_from, 'MMdd', 'jst')||'~'||td_time_format(after_to, 'MMdd', 'jst')
      end as span
    , if(dow(cast(business_date as date)) in (6, 7) or coalesce(hldy, 0) = 1, '土日祝', '平日') as dow_type
    , sum(td_time_slot) as td_time_slot
    , sum(entry_slot) as entry_slot
  from
    l2_integration_datamart.cls_sufficiency
    inner join shop_list using (property_id)
    left join (select substr(target_date, 1, 10) as business_date, 1 as hldy from _l1_mysql_pos.mst_holidays) using (business_date)
  group by
    1,2,3
)

select
  segment as "施策対象"
  , target_uu as "対象人数"
  , span as "期間"
  , type as "平日/土日祝"
  , sum(sales_amount)/1000 as "売上高1(千円)"
  , sum(order_count) as "施術件数(件)"
  , sum(order_count_new) as "新規施術件数(件)"
  , sum(treatment_minutes)/60 as "施術時間(h)"
  , sum(treatment_minutes)/cast(sum(order_count) as double) as "施術分数(分)"
  , sum(sales_amount)/cast(sum(order_count) as double) as "施術単価(円)"
  , sum(td_time_slot) as "必要枠(h)"
  , sum(entry_slot) as "受注時間(h)"
  , sum(entry_slot)/sum(td_time_slot) as "充足率(%)"
  , sum(treatment_minutes)/(sum(entry_slot)*60) as "稼働率(h)"
from
  cls_sufficiency
  left join (
    select *, '全日' as type from prep_orders
    union all select *, dow_type as type from prep_orders
  ) using (segment, span, dow_type)
  left join (select segment, count(distinct property_id) as target_uu from shop_list group by segment) using (segment)
where
  span is not null
group by
  1,2,3,4
order by
  1,2,3,4

