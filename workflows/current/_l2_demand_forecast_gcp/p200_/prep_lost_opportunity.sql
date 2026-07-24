select
  TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst') as time
  , mst_shop_id
  , substr('月火水木金土日', dow(cast(substr(treatment_dt, 1, 10) as timestamp)), 1) as business_dow
  , cast(substr(treatment_dt, 12, 2) as bigint) as business_hour
  , avg(loss_opps_fin) as loss_opps_fin
from
  z_lost_opportunity_analytics_fin_agg
where
  td_time_range(time, TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-28d', 'jst'), TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-0d', 'jst'), 'jst')
group by
  2,3,4