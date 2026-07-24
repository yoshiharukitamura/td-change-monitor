drop table if exists cls_time_slot_detail;
create table cls_time_slot_detail as 
select
  substr(date, 1, 10) as business_date
  , property_id
  , shop_no
  , shop_name
  , pref_name
  , pref_sort
  , therapist_id
  , therapist_no
  , therapist_name
  , td_time_add(td_time_parse(date, 'jst'), substr(start_time, 1, 2)||'h') as slot_from
  , td_time_add(td_time_parse(date, 'jst'), substr(end_time, 1, 2)||'h') as slot_to
  , cast(substr(start_time, 1, 2) as bigint) as business_hour
  , if(substr(end_time, 3, 2) = '30', 0.5, 1.0) as entry_slot
from
  time_slot_detail_current as t1
  inner join l2_integration_datamart.tp_info using (therapist_id)
  inner join l2_integration_datamart.shop_info using (property_id)
where
  t1.time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and coalesce(deleted, 0) = 0
  and division = 0
;


drop table if exists cls_sufficiency;
create table cls_sufficiency as 
select
  property_id
  , property_id as mst_shop_id
  , td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst') as business_week
  , substr('月火水木金土日', dow(cast(business_date as date)), 1) as business_dow
  , business_date
  , business_hour
  , td_time_slot
  , td1
  , td2
  , td3
  , entry_slot
  , treatment_minutes
  , sum(entry_slot) over (partition by dow(cast(business_date as date)), business_hour order by business_date rows between 4 preceding and 1 preceding)
    / sum(td_time_slot) over (partition by dow(cast(business_date as date)), business_hour order by business_date rows between 4 preceding and 1 preceding) as sufficiency_past_4week
  , sum(entry_slot) over (partition by dow(cast(business_date as date)), business_hour order by business_date rows between 8 preceding and 1 preceding)
    / sum(td_time_slot) over (partition by dow(cast(business_date as date)), business_hour order by business_date rows between 8 preceding and 1 preceding) as sufficiency_past_8week
  , sum(entry_slot) over (partition by dow(cast(business_date as date)), business_hour order by business_date rows between 15 preceding and 1 preceding)
    / sum(td_time_slot) over (partition by dow(cast(business_date as date)), business_hour order by business_date rows between 15 preceding and 1 preceding) as sufficiency_past_15week
  , nullif(treatment_minutes/60.0/entry_slot, 0) as utilization
from
  l2_integration_datamart.cls_td_time_slot_v1
  left join (
      select
        property_id
        , business_date
        , business_hour
        , sum(entry_slot) as entry_slot
      from
        cls_time_slot_detail
      group by
        1,2,3
    ) using (property_id, business_date, business_hour)
  left join (
      select
        property_id
        , business_date
        , business_hour
        , sum(treatment_minutes) as treatment_minutes
      from
        l2_integration_datamart.cls_orders
      group by
        1,2,3
    ) using (property_id, business_date, business_hour)
where
  td_time_parse(business_date, 'jst') between td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-7d') and td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '7d')
;