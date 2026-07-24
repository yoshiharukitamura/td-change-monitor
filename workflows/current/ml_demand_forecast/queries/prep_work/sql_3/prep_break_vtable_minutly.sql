select
  t1.*
  , t2.break_time
from
  prep_work_from_to as t1 cross join unnest (
      sequence(break_start_dt, break_end_dt, 60)
    ) AS t2(break_time)
where
  td_time_range(t1.time, '2020-08-01', td_scheduled_time(), 'jst')
  and t1.break_start_dt < t1.break_end_dt
  and t2.break_time < t1.break_end_dt
