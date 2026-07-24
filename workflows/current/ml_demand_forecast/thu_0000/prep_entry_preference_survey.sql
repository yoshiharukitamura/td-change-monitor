with latest_list as (
  select
    therapist_no
    , shop_name
    , max(answer_time) as answer_time
  from
    l2_demand_forecast_auto.${source_table}
  group by
    therapist_no
    , shop_name
)
, therapist_master as (
  select
    therapist_id
    , therapist_no
    , name as therapist_name
  from
    _l0_mysql_core.therapist
    inner join (select therapist_id, max(time) as time from _l0_mysql_core.therapist group by therapist_id) using (therapist_id, time)
)
, shop_master as (
  select
    property_id as shop_id
    , shop_no
    , shop_name
  from
    _l0_mysql_core.property
    inner join (select property_id, max(time) as time from _l0_mysql_core.property group by property_id) using (property_id, time)
)
, dow_date_mapping as (
  select
    lower(td_time_format(td_time_add(reference_date, cast(day_num as varchar)||'d'), 'EEE', 'jst')) as dow_key
    , substr('月火水木金土日', day_num+1, 1) as business_dow
    , td_time_string(td_time_add(reference_date, cast(day_num as varchar)||'d'), 'd!', 'jst') as business_date
  from
    (select '${reference_date}' as reference_date) as t0
    cross join unnest (sequence(0, 6, 1)) as t1(day_num)
)

select
  therapist_id
  , therapist_no
  , therapist_name
  , shop_id
  , shop_no
  , shop_name
  , business_date
  , dow_key
  , substr('00'||split(business_hour, '-')[1], length(split(business_hour, '-')[1])+1, 2) as business_hour_str
  , business_dow
  , cast(split(business_hour, '-')[1] as bigint) as business_hour
from (
    select
      substr('0000000'||therapist_no, length(therapist_no)+1, 7) as therapist_no
      , shop_name
      , dow_key
      , split(regexp_replace(business_hour_arr, '\s'), ',') as business_hour_arr
    from
      l2_demand_forecast_auto.${source_table}
      inner join latest_list using (therapist_no, shop_name, answer_time)
      cross join unnest (
        array['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']
        , array[mon, tue, wed, thu, fri, sat, sun]
      ) as dow_hours (dow_key, business_hour_arr)
  )
  cross join unnest (business_hour_arr) as tmp (business_hour)
  left join dow_date_mapping using (dow_key)
  left join therapist_master using (therapist_no)
  left join shop_master using (shop_name)
where
  length(business_hour) > 0
order by
  therapist_no
  , shop_name
  , business_date
  , business_hour
