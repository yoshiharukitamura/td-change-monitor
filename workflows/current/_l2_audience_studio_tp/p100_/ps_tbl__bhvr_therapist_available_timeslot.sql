with prep_td_timeslot as (
  select
    business_date
    , shop_no
    , shop_name
    , business_dow
    , business_hour
    , date_format(
        date_parse(substr(business_date, 1, 10) || ' 00:00:00', '%Y-%m-%d %H:%i:%s')
        + (cast(floor(cast(substr(cast(business_hour as varchar), 1, 2) as integer) / 24.0) as integer) * interval '1' day)
        + ((cast(substr(cast(business_hour as varchar), 1, 2) as integer) % 24) * interval '1' hour),
        '%Y-%m-%d %H:%i:%s'
      ) as time_slot
    , td_time_slot
    , td1
    , td2
    , td3
    , if(coalesce(entry_slot, 0) < td1, 'yes', null) as not_enough_td1
    , if(coalesce(entry_slot, 0) < td1 + td2, 'yes', null) as not_enough_td2
    , if(coalesce(entry_slot, 0) < td1 + td2 + td3, 'yes', null) as not_enough_td3
    , lag(utilization) over (partition by property_id, business_dow, business_hour order by business_week) as last_week_util
  from
    _integration_datamart.cls_sufficiency
    left join (select property_id, shop_no, shop_name from _integration_datamart.mst_shop) using (property_id)
  where
    td_time_parse(business_date, 'jst') >= td_date_trunc('day', td_scheduled_time(), 'jst')
    and coalesce(entry_slot, 0) < (td1 + td2 + td3)
)

, tp_entry as (
  select
    shop_no
    , therapist_no
    , td_time_string(td_date_trunc('hour', slot_from, 'jst'), 's!', 'jst') as time_slot
    , count(1) as todays_entry_count
  from
    _integration_datamart.cls_time_slot_detail
  where
    td_time_parse(business_date, 'jst') > td_date_trunc('day', td_scheduled_time(), 'jst')
  group by
    1,2,3
)

, last_4week_tp_entry as (
  select distinct
    therapist_no
    , shop_no
  from
    _integration_datamart.cls_time_slot_detail
  where
    td_time_range(time, td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-4w'), td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '1w'), 'jst')
)

, candidate_ts as (
  select
    shop_no
    , shop_name
    , therapist_no
    , business_date
    , business_dow
    , business_hour
    , time_slot
    , td_time_slot
    , td1
    , td2
    , td3
    , not_enough_td1
    , not_enough_td2
    , not_enough_td3
    , last_week_util
  from
    prep_td_timeslot
    inner join
      last_4week_tp_entry
      using (shop_no)
)

select
  td_time_parse(t0.time_slot, 'jst') as time
  , t0.therapist_no as mstr__id
  , t0.shop_no
  , shop_name
  , td_time_parse(t0.time_slot, 'jst') as timeslot_datetime
  , business_dow
  , business_hour
  , td_time_slot * 60.0 as td_minuites
  , td1 * 60.0 as td1_minuites
  , td2 * 60.0 as td2_minuites
  , td3 * 60.0 as td3_minuites
  , not_enough_td1
  , not_enough_td2
  , not_enough_td3
  , last_week_util * 60 as last_week_util
from
  candidate_ts as t0
  left join
    tp_entry as t1
    on t0.shop_no = t1.shop_no
       and t0.therapist_no = t1.therapist_no
       and t0.time_slot = t1.time_slot
where
  t1.therapist_no is null