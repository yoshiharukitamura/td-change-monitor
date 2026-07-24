with therapist_master as (
  select
    therapist_id
    , therapist_no
    , name as therapist_name
  from
    _l1_mysql_core.therapist
)
, shop_master as (
  select
    property_id as shop_id
    , shop_no
    , shop_name
    , latest_bed_num
  from
    _l1_mysql_core.property
)

select distinct
  application_time_slot_id
  , t1.therapist_id
  , t1.therapist_no
  , t1.therapist_name
  , t2.shop_id
  , t2.shop_no
  , t2.shop_name
  , t2.latest_bed_num
  , substr(t0.date, 1, 10) as business_date
  , '' as dow_key
  , substr(t0.start_time, 1, 2) as business_hour_str
  , substr('月火水木金土日', dow(cast(substr(t0.date, 1, 10) as date)), 1) as business_dow
  , cast(substr(t0.start_time, 1, 2) as bigint) as business_hour
from
  _l0_mysql_core.application_time_slot as t0
  left join therapist_master as t1 on t0.therapist_id = t1.therapist_id
  left join shop_master as t2 on t0.property_id = t2.shop_id
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and adoption_flag is null
  and deleted = 0
