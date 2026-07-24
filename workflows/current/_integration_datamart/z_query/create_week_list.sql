with datetime_list_raw as (
  select distinct
    td_time_add(
        td_time_add(cast(reference_year + year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst')
        , cast(hour_num as varchar)||'h'
        , 'jst'
      ) as datetime
  from
    (select 2016 as reference_year) as t0
    cross join unnest (sequence(0, 99, 1)) as t1(year_num)
    cross join unnest (sequence(0, 365, 1)) as t2(day_num)
    cross join unnest (sequence(0, 23, 1)) as t3(hour_num)
)

select distinct
  td_date_trunc('week', datetime, 'jst') as business_week
from
  datetime_list_raw
where
  td_time_range(td_date_trunc('week', datetime, 'jst'), '2024-01-01', '2025-01-22', 'jst')
order by
  1
