with prep as (
  select
    customerid_deviceid
    , td_time_string(td_time_add(session_start_date, '-1d', 'jst'), 'd!', 'jst') as session_start_date
    , 1 as is_loss_opps_yesterday
  from
    l1_datamart_202210.z_lost_opportunity_analytics_raw_tmp
  where
    loss_opps = 1
  group by
    1,2
)

select
  *
from
  l1_datamart_202210.z_lost_opportunity_analytics_raw_tmp
  left join prep using (customerid_deviceid, session_start_date)