with list as (
  select distinct
    therapist_id
    , start_date
    , end_date
    , td_time_string(time, 's!', 'jst') as import_datetime
  from
    quest_stop_tp_list_history
  where
    time = td_time_add(td_scheduled_time(), '-7d', 'jst')
    and start_date = td_time_string(td_date_trunc('week', td_scheduled_time(), 'jst'), 'd!', 'jst')

  union all

  select distinct
    therapist_id
    , start_date
    , end_date
    , td_time_string(time, 's!', 'jst') as import_datetime
  from
    quest_stop_tp_list_history
  where
    time = td_scheduled_time()
    and start_date = td_time_string(td_date_trunc('week', td_time_add(td_scheduled_time(), '7d', 'jst'), 'jst'), 'd!', 'jst')
)

select distinct
  therapist_id
  , start_date
  , end_date
from
  list
order by
  1,2,3
