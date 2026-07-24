select distinct
  application_time_slot_id
  , therapist_id
  , property_id
  , substr(date, 1, 10) as date
  , start_time
  , end_time
  , if(regexp_like(result_hv, '当選|救済'), 1, 0) as adoption_flag
from
  _l0_mysql_core.application_time_slot
  left join (select application_time_slot_id, result_hv from l2_demand_forecast_auto.timeslot_entry_elected_result_hv) using (application_time_slot_id)
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and adoption_flag is null
  and deleted = 0
