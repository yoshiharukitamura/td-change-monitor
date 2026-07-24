with datetime_list as (
  select distinct
    td_time_add(
        td_time_add(cast(reference_year + year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst')
        , cast(hour_num as varchar)||'h'
        , 'jst'
      ) as datetime
  from
    (select 2000 as reference_year) as t0
    cross join unnest (sequence(0, 99, 1)) as t1(year_num)
    cross join unnest (sequence(0, 365, 1)) as t2(day_num)
    cross join unnest (sequence(0, 23, 1)) as t3(hour_num)
)
, trunc_date_list as (
  select distinct
    td_date_trunc('${split}', datetime, 'jst') as trunc_date
  from
    datetime_list
  where
    td_date_trunc('day', datetime, 'jst') between td_time_parse('${date_from}', 'jst') and td_time_parse('${date_to}', 'jst')
)

select
  td_time_string(trunc_date, 'd!', 'jst') as date_from
  , coalesce(td_time_string(td_time_add(lead(trunc_date) over (order by trunc_date), '-1d'), 'd!', 'jst'), '${date_to}') as date_to
  , cast(trunc_date = first_value(trunc_date) over (order by trunc_date) as boolean) as is_1st_process
from
  trunc_date_list
order by
  trunc_date
