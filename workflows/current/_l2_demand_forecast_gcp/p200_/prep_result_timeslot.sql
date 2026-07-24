select
  *
  , avg(result_timeslot_value) over (partition by mst_shop_id, business_dow, business_hour order by result_datetime rows between 7 preceding and 0 preceding) as avg_result_timeslot_value
from (
    select
      time
      , business_date as processing_date
      , property_id as mst_shop_id
      , business_datetime as result_datetime
      , td_time_string(td_date_trunc('week', time, 'jst'), 'd!', 'jst') as business_week
      , business_dow
      , business_hour
      , sum(time_slot) as result_timeslot_value
    from
      prep_time_slot_hourly
    where
        td_time_range(time, '2020-01-01', td_time_add(td_scheduled_time(), '8week', 'jst'), 'jst')
        and business_hour between 9 and 23
    group by
      1,2,3,4,5,6,7
  )
