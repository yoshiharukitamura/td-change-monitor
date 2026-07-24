with shop_list as (
  select distinct
    property_id
    , segment
    , td_time_parse(before_from, 'jst') as before_from
    , td_time_parse(before_to, 'jst') as before_to
    , td_time_parse(after_from, 'jst') as after_from
    , least(td_time_parse(after_to, 'jst'), ${moment(session_date).subtract(1, 'day').unix()}) as after_to
  from
    ${td.database}.list_${tbl.td_tbl_name}
    left join (select shop_no, property_id from l2_integration_datamart.shop_info) using (shop_no)
)

, customer_rf as (
  select 
    distinct 
    customer_id
    , processing_date as business_date
    , r_week 
  from _integration_datamart.hst_daily_customer_rf
  where time >= td_time_parse('2025-12-01', 'jst')
)

, cls_order as (
  select
    time
    , business_date
    , order_id
    , customer_id
    , property_id
    , treatment_minutes
    , uriage1
    , treatment_minutes_in_hour
    , order_detail_id_seq
    , order_id_hour_seq
    , is_repeat
  from
    _integration_datamart.cls_order_detail
  where
    time >= td_time_parse('2025-12-01', 'jst')
)

, prep_orders as (
  select
    segment
    , case
        when t0.time between before_from and before_to
          then '実施前:'||td_time_format(before_from, 'MMdd', 'jst')||'~'||td_time_format(before_to, 'MMdd', 'jst')
        when t0.time between after_from and after_to
          then '実施中:'||td_time_format(after_from, 'MMdd', 'jst')||'~'||td_time_format(after_to, 'MMdd', 'jst')
      end as span
    , if(dow(cast(t0.business_date as date)) in (6, 7) or coalesce(hldy, 0) = 1, '土日祝', '平日') as dow_type
    , count(distinct if(treatment_minutes>0, order_id)) as order_count
    , count(distinct if(treatment_minutes>0 and is_repeat = 0, order_id)) as order_count_new
    , count(distinct if(treatment_minutes>0 and r_week >= 13, order_id)) as order_count_rw13over
    , sum(if(order_detail_id_seq = 1, treatment_minutes_in_hour)) as treatment_minutes
    , sum(if(order_id_hour_seq = 1, uriage1)) as sales_amount
  from
    cls_order as t0
    inner join shop_list as t1
    on t0.property_id = t1.property_id
    and t0.time between t1.before_from and t1.after_to
    left join (select substr(target_date, 1, 10) as business_date, 1 as hldy from _l1_mysql_pos.mst_holidays) as t2
    on t0.business_date = t2.business_date
    left join customer_rf as t3
    on t0.customer_id = t3.customer_id
    and t0.business_date = t3.business_date
  where
    is_repeat = 0
  group by
    1,2,3
)

, cls_sufficiency as (
  select
    segment
    , case
        when t0.time between before_from and before_to
          then '実施前:'||td_time_format(before_from, 'MMdd', 'jst')||'~'||td_time_format(before_to, 'MMdd', 'jst')
        when t0.time between after_from and after_to
          then '実施中:'||td_time_format(after_from, 'MMdd', 'jst')||'~'||td_time_format(after_to, 'MMdd', 'jst')
      end as span
    , if(dow(cast(t0.business_date as date)) in (6, 7) or coalesce(hldy, 0) = 1, '土日祝', '平日') as dow_type
    , sum(td_time_slot) as td_time_slot
    , sum(entry_slot) as entry_slot
  from
    _integration_datamart.cls_sufficiency as t0
    inner join shop_list as t1
    on t0.property_id = t1.property_id
       and t0.time between t1.before_from and t1.after_to
    left join (select substr(target_date, 1, 10) as business_date, 1 as hldy from _l1_mysql_pos.mst_holidays) as t2
    on t0.business_date = t2.business_date
  where
    time >= td_time_parse('2025-12-01', 'jst')
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
  , sum(order_count_rw13over) as "R/w13+施術件数(件)"
  , sum(order_count_new) + sum(order_count_rw13over) as "新規+R/w13+施術件数(件)"
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
