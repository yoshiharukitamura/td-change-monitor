select
  week
  , r_week
  , f
  , customer_id
  , shop_no_last_order
  , shop_name as shop_name_last_order
from _integration_datamart.hst_weekly_customer_rf
left join (select cast(shop_no as integer) as shop_no_last_order, shop_name from _integration_datamart.mst_shop) using (shop_no_last_order)
where time = td_date_trunc('week', td_scheduled_time(), 'jst')
      and r_week <= 52