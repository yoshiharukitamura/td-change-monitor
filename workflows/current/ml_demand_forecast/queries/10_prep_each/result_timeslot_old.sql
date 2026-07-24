select
  processing_date as time
  , td_time_format(processing_date, 'YYYY-MM-dd', 'jst') as processing_date
  , mst_shop_id
  , result_datetime
  , business_week
  , business_dow
  , business_hour
  , result_timeslot_value
  , avg(result_timeslot_value) over (partition by mst_shop_id, business_dow, business_hour order by result_datetime rows between 7 preceding and 0 preceding) as avg_result_timeslot_value
from (
  select
    td_time_add(td_date_trunc('week', td_time_parse(work_time, 'jst'), 'jst'), '7d', 'jst') as processing_date
    , mst_shop_id
    , work_time as result_datetime
    , substr(work_time, 1, 10) as business_day
    , td_time_format(td_date_trunc('week', td_time_parse(work_time, 'jst'), 'jst'), 'YYYY-MM-dd', 'jst') as business_week
    , substr('月火水木金土日', dow(cast(work_time as timestamp)), 1) as business_dow
    , cast(substr(work_time, 12, 2) as bigint) as business_hour
    , work_count as result_timeslot_value
  from
    l1_datamart.prep_workbreak_vtable_minutely
  where
    td_time_range(time, '2020-01-01', td_time_add(td_scheduled_time(), '8week', 'jst'), 'jst')
    and cast(substr(work_time, 12, 2) as bigint) between 9 and 23
    and work_count > 0
)

