with tp_info as (
  select
    therapist_id
    , therapist_no
    , therapist_name
    , division
    , gender
    , age
    , hope_property_id_1
    , hope_property_id_2
    , work_saturday
    , work_sunday
    , work_holiday
    , week_days
    , timezone
  from
    _integration_datamart.mst_therapist
  where
    division = 0
)
, shop_info as (
  select
    property_id
    , shop_no
    , status
    , status_name
    , business_start_time
    , business_end_time
    , latest_bed_num
    , pref_name
    , area_name
    , market_population_1km
    , market_population_3km
  from
    _integration_datamart.mst_shop
  where
    status = '02'
)

select
  td_time_parse(substr(date, 1, 10), 'jst') as time
  , td_time_string(td_time_parse(substr(date, 1, 10), 'jst'), 's!', 'jst') as time_fmt
  , 'business_date' as time_means
  , therapist_id
  , property_id
  , substr(date, 1, 10) as business_date
  , cast(substr(start_time, 1, 2) as bigint) as business_hour
  , td_time_add(td_time_parse(date, 'jst'), substr(start_time, 1, 2)||'h') as slot_from
  , td_time_add(td_time_parse(date, 'jst'), substr(end_time, 1, 2)||'h') as slot_to
  , if(substr(end_time, 3, 2) = '30', 0.5, 1.0) as entry_slot
  , tp_info.*
  , shop_info.*
from
  _l0_mysql_core.time_slot_detail
  inner join (
    select time_slot_detail_id, max(time) as time
    from _l0_mysql_core.time_slot_detail
    group by time_slot_detail_id
  ) using (time_slot_detail_id, time)
  inner join tp_info using (therapist_id)
  inner join shop_info using (property_id)
where
  coalesce(deleted, 0) = 0
