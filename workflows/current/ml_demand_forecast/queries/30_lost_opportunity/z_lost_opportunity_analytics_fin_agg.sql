select
  time
  , mst_shop_id
  , mst_shop_no
  , mst_shop_name
  , pref_id
  , pref_name
  , pref_sort_order
  , area_id
  , area_name
  , area_sort_order
  , treatment_dt
  , round(sum(loss_opps_tmp * lost_opportunity_rate / split_count), 2) as loss_opps_tmp
  , round(sum(loss_opps_fin * lost_opportunity_rate / split_count), 2) as loss_opps_fin
from
  l1_datamart_202210.z_lost_opportunity_analytics_fin
where
  td_time_range(time, TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-28d', 'jst'), TD_TIME_ADD(TD_DATE_TRUNC('week', TD_SCHEDULED_TIME(), 'jst'), '-0d', 'jst'), 'jst')
group by
  time
  , mst_shop_id
  , mst_shop_no
  , mst_shop_name
  , pref_id
  , pref_name
  , pref_sort_order
  , area_id
  , area_name
  , area_sort_order
  , treatment_dt