select
  customerid_deviceid
  , customer_id
  , session_start_date
  , td_time_parse(session_start_date, 'jst') as time
  , min(session_start_time) as session_start_time
  , array_distinct(flatten(array_agg(arry_mst_shop_no) filter(where arry_mst_shop_no is not null))) as arry_mst_shop_no
  , sum(pv_shop_detail) as pv_shop_detail
  , sum(pv_reservation_confirm) as pv_reservation_confirm
  , sum(pv_reservation_complete) as pv_reservation_complete
  , sum(pv_reservation_change) as pv_reservation_change
  , sum(pv_sci) as pv_sci
  , sum(pv_notification) as pv_notification
  , sum(pv_reservation_history) as pv_reservation_history
  , sum(pv_shop_serach) as pv_shop_serach
  , sum(pv_reservation_history_before_reserve) as pv_reservation_history_before_reserve
  , max(is_therapy_date) as is_therapy_date
  , max(is_therapy_date_1ago) as is_therapy_date_1ago
  , max(is_reserve_within_1day) as is_reserve_within_1day
  , max(is_reserve_within_2day) as is_reserve_within_2day
  , max(is_reserve_within_3day) as is_reserve_within_3day
  , max(is_reserve_0day) as is_reserve_0day
  , min(reservation_dt) as reservation_dt
  , min(treatment_dt) as treatment_dt
  , sum(stay_sec) as stay_sec
  , min_by(reservation_dow, coalesce(reservation_dt, session_start_time)) as reservation_dow
  , min_by(reservation_hour, coalesce(reservation_dt, session_start_time)) as reservation_hour
  , min(date_diff_reserve_treat) as date_diff_reserve_treat
  , min_by(treatment_hour, treatment_dt) as treatment_hour
  , max(loss_opps)*0.831 as loss_opps_tmp
  , max(if(loss_opps=1 and is_loss_opps_yesterday is null, 1, 0))*0.831 as loss_opps_fin
from
  z_lost_opportunity_analytics_raw
group by
  customerid_deviceid
  , customer_id
  , session_start_date