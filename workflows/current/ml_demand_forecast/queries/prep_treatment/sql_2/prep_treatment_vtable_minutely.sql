select
  t1.*
  , t2.treatment_time
from
  prep_treatment_from_to as t1
  cross join unnest (
    sequence(raw_treatment_start_time, raw_treatment_end_time, 60)
  ) AS t2(treatment_time)
where
  td_time_range(time, null, td_time_add(td_scheduled_time(), '1d', 'jst'), 'jst')
  and t2.treatment_time is not null
  and t2.treatment_time<t1.raw_treatment_end_time
