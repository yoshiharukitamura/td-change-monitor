select
  processing_date
  , cluster_no
  , cluster_no as cluster_id
  , cast(regexp_replace(s_property_id, '^s', '') as bigint) as mst_shop_id
  , business_datetime as forecast_datetime
  , date_diff('week', cast(processing_date as date),cast(substr(business_datetime, 1, 10) as date)) as weeks_ahead
  , td_time_string(td_date_trunc('week', td_time_parse(business_datetime, 'jst'), 'jst'), 'd!', 'jst') as business_week
  , substr(business_datetime, 1, 10) as business_day
  , weekday as business_dow
  , hour as business_hour
  , yhat * allocation_value as forecast_treatment_value
from
  _l2_demand_forecast_gcp.forecast_result_by_cluster
  left join (
    select distinct
      processing_date
      , cluster_no
      , business_datetime
      , s_property_id
      , allocation_value
    from
      _l2_demand_forecast_gcp.forecast_rebate_coefficient
  ) using (processing_date, cluster_no, business_datetime)
;
