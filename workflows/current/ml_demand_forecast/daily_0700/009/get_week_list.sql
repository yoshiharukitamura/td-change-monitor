select
  forecast_week as reference_week
from
  l2_demand_forecast_auto.fin_timeslot_raw_vtable 
where
  forecast_week >= '2023-07-24'
  and weeks_ahead_riraku = 0
group by
  forecast_week
order by
  reference_week
