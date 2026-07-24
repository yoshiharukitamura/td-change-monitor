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
, prep_orders as (
  select
    property_id
    , business_date
    , business_hour
    , sum(treatment_minutes) as treatment_minutes 
  from
    l2_integration_datamart.cls_orders
  group by
    1,2,3
)
, prep_sufficiency as (
  select
    property_id
    , segment
    , business_date
    , business_hour
    , case
        when td_time_parse(business_date, 'jst') between before_from and before_to
          then '実施前:'||td_time_format(before_from, 'MMdd', 'jst')||'~'||td_time_format(before_to, 'MMdd', 'jst')
        when td_time_parse(business_date, 'jst') between after_from and after_to
          then '実施中:'||td_time_format(after_from, 'MMdd', 'jst')||'~'||td_time_format(after_to, 'MMdd', 'jst')
      end as span
    , if(dow(cast(business_date as date)) in (6, 7) or coalesce(hldy, 0) = 1, '土日祝', '平日') as dow_type
    , case
        when dow(cast(business_date as date)) not in (6, 7) and coalesce(hldy, 0) = 0 and business_hour between 18 and 23 then '逆L字'
        when dow(cast(business_date as date)) in (6, 7) or coalesce(hldy, 0) = 1 and business_hour between 9 and 23 then '逆L字'
        when business_hour between 9 and 23 then 'その他'
      end as hour_type
    , sum(td_time_slot) as td_time_slot
    , sum(entry_slot) as entry_slot
  from
    l2_integration_datamart.cls_sufficiency
    left join (select substr(target_date, 1, 10) as business_date, 1 as hldy from _l1_mysql_pos.mst_holidays) using (business_date)
    inner join shop_list using (property_id)
  group by
    1,2,3,4,5,6,7
)

select
  segment as "施策対象"
  , target_uu as "対象店舗"
  , span as "期間"
  , type as "逆L字/その他"
  , sum(td_time_slot) as "必要枠(h)"
  , sum(entry_slot) as "受注時間(h)"
  , sum(treatment_minutes)/60 as "施術時間(h)"
  , sum(entry_slot)/sum(td_time_slot) as "充足率(%)"
  , sum(treatment_minutes)/sum(entry_slot*60) as "稼働率(%)"
from (
    select *, '合計' as type from prep_sufficiency
    union all select *, hour_type as type from prep_sufficiency
  )
  left join prep_orders using (property_id, business_date, business_hour)
  left join (select segment, count(distinct property_id) as target_uu from shop_list group by segment) using (segment)
where
  span is not null
  and hour_type is not null
group by
  1,2,3,4
order by
  1,2,3,4
