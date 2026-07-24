select
  t1.*
  , t2.work_time
from
  prep_work_from_to as t1 cross join unnest (
      sequence(start_dt, end_dt, 60)
    ) AS t2(work_time)
where
  td_time_range(t1.time, '2020-08-01', td_scheduled_time(), 'jst')
  and t1.start_dt < t1.end_dt
  and t2.work_time < t1.end_dt