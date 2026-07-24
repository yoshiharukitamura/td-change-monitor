with diff_list as (
  select
    mst_shop_id
    , treatment_time
    , cast(if(coalesce(timeslot_result, 0) < timeslot_td * 60 and coalesce(treatment_minutes, 0) < forecast_value and td_time_format(treatment_time, 'HH', 'jst') >= '20', forecast_value, null) as bigint) as treatment_count_fixed_1
    , cast(if(coalesce(timeslot_result, 0) < timeslot_td * 60 and coalesce(treatment_minutes, 0) < forecast_value and td_time_format(treatment_time, 'HH', 'jst') >= '20', forecast_value + loss_opps_fin_value, null) as bigint) as treatment_count_fixed_2
    -- , cast(if(coalesce(timeslot_result, 0) < timeslot_td * 60, forecast_value + loss_opps_fin_value, null) as bigint) as treatment_count_fixed_2
    , cast(if(coalesce(timeslot_result, 0) < timeslot_td * 60, timeslot_td * 60 * 0.58, null) as bigint) as treatment_count_fixed_3
  from
    check_forecast_diff
)

select
  time
  , mst_shop_id
  , treatment_time
  , coalesce(treatment_count_fixed_2, treatment_count) as treatment_count
from
  prep_treatment_vtable_hourly
  left join diff_list using (mst_shop_id, treatment_time)
