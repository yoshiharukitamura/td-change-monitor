select
  processing_date as time
  , td_time_format(processing_date, 'YYYY-MM-dd', 'jst') as processing_date
  , mst_shop_id
  , result_datetime
  , business_day
  , business_week
  , business_dow
  , business_hour
  , result_treatment_value
  , avg(result_treatment_value) over (partition by mst_shop_id, business_dow, business_hour order by result_datetime rows between 7 preceding and 0 preceding) as avg_result_treatment_value
from (
  select
    td_time_add(td_date_trunc('week', treatment_time, 'jst'), '7d', 'jst') as processing_date
    , mst_shop_id
    , td_time_string(treatment_time, 's!', 'jst') as result_datetime
    , td_time_format(treatment_time, 'YYYY-MM-dd', 'jst') as business_day
    , td_time_format(td_date_trunc('week', treatment_time, 'jst'), 'YYYY-MM-dd', 'jst') as business_week
    , substr('月火水木金土日', dow(cast(td_time_string(treatment_time, 's!', 'jst') as timestamp)), 1) as business_dow
    , cast(td_time_format(treatment_time, 'HH', 'jst') as bigint) as business_hour
    , treatment_count as result_treatment_value
  from
    l1_datamart.prep_treatment_vtable_hourly
  where
    td_time_range(time, '2020-01-01', td_scheduled_time(), 'jst')
    and cast(td_time_format(treatment_time, 'HH', 'jst') as bigint) between 9 and 23
    and treatment_count > 0
)
