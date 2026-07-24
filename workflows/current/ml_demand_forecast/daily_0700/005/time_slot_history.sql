select
  td_time_parse(forecast_week, 'jst') as time
  , forecast_week as business_week
  , processing_date_riraku as processing_week
  , weeks_ahead_riraku as offset_diff
  , mst_shop_id as shop_id
  , business_day as business_date
  , business_hour
  , time_slot
  , td1
  , td2
  , td1+td2 as td12
  , td3
  , td1+td2+td3 as td123
from
  l2_demand_forecast_auto.fin_timeslot_raw_vtable_fixed
