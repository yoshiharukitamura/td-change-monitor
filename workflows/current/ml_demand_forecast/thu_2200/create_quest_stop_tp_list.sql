with therapist_master as (
  select distinct 
    therapist_id
    , cast(cast(therapist_no as bigint) as varchar) as therapist_no
  from
    _l1_mysql_core.therapist
  where
    therapist_no is not null
)
, prep as (
  select
    therapist_id
    , td_time_string(td_date_trunc('week', td_time_parse(target_week, 'jst'), 'jst'), 'd!', 'jst') as start_date
    , td_time_string(td_time_add(td_date_trunc('week', td_time_parse(target_week, 'jst'), 'jst'), '6d', 'jst'), 'd!', 'jst') as end_date
  from
    l2_demand_forecast_auto.spreadsheets_quest_stop_list
    left join therapist_master using (therapist_no)
  where
    time = td_scheduled_time()
    and td_date_trunc('week', td_time_parse(target_week, 'jst'), 'jst') = td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '7d', 'jst')
)
, prep_2 as (
  select
    therapist_id
    , td_time_string(td_time_add(start_date, '7d', 'jst'), 'd!', 'jst') as start_date
    , td_time_string(td_time_add(end_date, '7d', 'jst'), 'd!', 'jst') as end_date
  from
    prep
)

select distinct
  td_scheduled_time() as time
  , *
from (
  select * from prep
  union all select * from prep_2
)
order by
  therapist_id
  , start_date
