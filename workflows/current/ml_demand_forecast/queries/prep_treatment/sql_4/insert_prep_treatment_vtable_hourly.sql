select distinct
  td_date_trunc('day', td_time_add(td_time_add(td_time_add(cast(reference_year+year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst'), cast(hour_num as varchar)||'h', 'jst'), '-6h', 'jst'), 'jst') as time
  -- , td_time_string(td_date_trunc('day', td_time_add(td_time_add(td_time_add(cast(reference_year+year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst'), cast(hour_num as varchar)||'h', 'jst'), '-6h', 'jst'), 'jst'), 's!', 'jst') as time_fmt_jst
  , 0 as mst_shop_id
  , td_time_add(td_time_add(cast(reference_year+year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst'), cast(hour_num as varchar)||'h', 'jst') as treatment_time
  -- , td_time_string(td_time_add(td_time_add(cast(reference_year+year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst'), cast(hour_num as varchar)||'h', 'jst'), 's!', 'jst') as treatment_time_fmt_jst
  , 0 as treatment_count
from
  (select 2018 as reference_year) as t1
  cross join unnest (
      sequence(0, 99, 1)
    ) AS t2(year_num)
  cross join unnest (
      sequence(0, 365, 1)
    ) AS t3(day_num)
  cross join unnest (
      sequence(0, 23, 1)
    ) AS t4(hour_num)
where
  td_time_range(
    td_time_add(td_time_add(cast(reference_year+year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst'), cast(hour_num as varchar)||'h', 'jst')
    , td_time_parse('2018-01-01 06:00:00', 'jst')
    , td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '6h', 'jst')
    , 'jst'
  )
order by
  1,2,3,4