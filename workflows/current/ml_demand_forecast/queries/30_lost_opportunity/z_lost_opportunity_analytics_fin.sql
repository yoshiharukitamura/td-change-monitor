with lost_opportunity_param as (
  select
    reservation_dow
    , reservation_hour
    , date_diff_reserve_treat
    , treatment_hour
    , cast(session_count as double)/session_count_all as lost_opportunity_rate
  from (
      select
        reservation_dow
        , reservation_hour
        , date_diff_reserve_treat
        , treatment_hour
        , count(1) as session_count 
      from
        l1_datamart_202210.z_lost_opportunity_analytics_raw_by_user
      where
        td_time_range(time, TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-35d', 'jst'), TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-7d', 'jst'), 'jst')
        and reservation_dt < treatment_dt
        and date_diff_reserve_treat between 0 and 7
        and cast(treatment_hour as bigint) between 8 and 23
      group by
        reservation_dow
        , reservation_hour
        , date_diff_reserve_treat
        , treatment_hour
  ) left join (
      select
        reservation_dow
        , reservation_hour
        , count(1) as session_count_all
      from
        l1_datamart_202210.z_lost_opportunity_analytics_raw_by_user
      where
        td_time_range(time, TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-35d', 'jst'), TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-7d', 'jst'), 'jst')
        and reservation_dt < treatment_dt
        and date_diff_reserve_treat between 0 and 7
        and cast(treatment_hour as bigint) between 8 and 23
      group by
        reservation_dow
        , reservation_hour
  ) using (reservation_dow, reservation_hour)
)

select
  td_time_parse(td_time_string(td_time_add(session_start_date, cast(t2.date_diff_reserve_treat as varchar)||'d', 'jst'), 'd!', 'jst')||' '||t2.treatment_hour||':00:00', 'jst') as time
  , mst_shop_id
  , mst_shop_no
  , mst_shop_name
  , pref_id
  , pref_name
  , pref_sort_order
  , area_id
  , area_name
  , area_sort_order
  , split_count
  , t1.reservation_dow
  , t1.reservation_hour
  , loss_opps_tmp
  , loss_opps_fin
  , t2.date_diff_reserve_treat
  , t2.treatment_hour
  , td_time_string(td_time_add(session_start_date, cast(t2.date_diff_reserve_treat as varchar)||'d', 'jst'), 'd!', 'jst')||' '||t2.treatment_hour||':00:00' as treatment_dt
  , lost_opportunity_rate
from
  l1_datamart_202210.z_lost_opportunity_analytics_flag as t1
  left join lost_opportunity_param as t2 on t1.reservation_dow=t2.reservation_dow and t1.reservation_hour=t2.reservation_hour
where
  td_time_range(time, TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-42d', 'jst'), TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-0d', 'jst'), 'jst')
  and (loss_opps_tmp+loss_opps_fin)>0