with prep_rebate_coef as (
  select
    t1.processing_date
    , t1.week as week
    , cast(regexp_replace(t1.mst_shop_id, '^s', '') as bigint) as mst_shop_id
    , cast(regexp_replace(t2.key, '^allocation_value_', '') as bigint) as business_hour
    , if(t2.value < 0, 0, t2.value) as coef
  from
    forecast_rebate_coefficient as t1
    cross join unnest (
      array['allocation_value_09', 'allocation_value_10', 'allocation_value_11', 'allocation_value_12', 'allocation_value_13', 'allocation_value_14', 'allocation_value_15', 'allocation_value_16', 'allocation_value_17', 'allocation_value_18', 'allocation_value_19', 'allocation_value_20', 'allocation_value_21', 'allocation_value_22', 'allocation_value_23'],
      array[allocation_value_9, allocation_value_10, allocation_value_11, allocation_value_12, allocation_value_13, allocation_value_14, allocation_value_15, allocation_value_16, allocation_value_17, allocation_value_18, allocation_value_19, allocation_value_20, allocation_value_21, allocation_value_22, allocation_value_23]
    ) as t2 (key, value)
)
-- , adjust_rebate_coef as (
--   select
--     processing_date
--     , week as week   
--     , cast(regexp_replace(mst_shop_id, '^s', '') as bigint) as mst_shop_id
--     , (allocation_value_17 + allocation_value_18 + allocation_value_19) / 3 as coef
--   from
--     forecast_rebate_coefficient
-- )
, tmp_cluster_result as (
  select
    t2.processing_date
    , t1.id as mst_shop_id
    , coalesce(t3.cluster_id, 4) as cluster_id
  from
    l1_pos.mst_shops as t1
    left join (
        select
          processing_date
        from
          forecast_clustering_result
        group by
          processing_date
      ) as t2 on t1.id is not null
    left join (
        select
          processing_date
          , mst_shop_id
          , cluster_id
        from
          forecast_clustering_result
      ) as t3 on t1.id = t3.mst_shop_id and t2.processing_date = t3.processing_date
)
, prep_cluster_result as (
  select
    t0.processing_date
    , t0.mst_shop_id
    , t0.cluster_id
    , t123.mst_shop_no
    , t123.mst_shop_name
    , t123.mst_pref_id
    , t123.mst_pref_name
    , t123.mst_pref_sort_order
    , t123.mst_area_id
    , t123.mst_area_name
    , t123.mst_area_sort_order
  from
    tmp_cluster_result as t0
    left join (
        select
          t1.id as mst_shop_id
          , t1.no as mst_shop_no
          , t1.name as mst_shop_name
          , t1.pref_id as mst_pref_id
          , t2.name as mst_pref_name
          , t2.sort_order as mst_pref_sort_order
          , t1.mst_area_id as mst_area_id
          , t3.name as mst_area_name
          , t3.sort_order as mst_area_sort_order
        from
          _l1_mysql_pos.mst_shops as t1
          left join _l1_mysql_pos.mst_prefectures as t2 on t1.pref_id = t2.id
          left join _l1_mysql_pos.mst_areas as t3 on t1.mst_area_id = t3.id
      ) as t123 on t0.mst_shop_id = t123.mst_shop_id
)
, prep_forecast_by_cluster as (
  select
    processing_date
    , cluster_id
    , forecast_datetime
    , cast(substr(forecast_datetime, 12, 2) as bigint) as business_hour
    , forecast_value
    , week
  from
    forecast_predict_result_by_cluster
-- union all
--   select
--     processing_date
--     , cluster_id
--     , regexp_replace(forecast_datetime, '10:00:00', '09:00:00') as forecast_datetime
--     , 9 as business_hour
--     , forecast_value
--     , week
--   from
--     forecast_predict_result_by_cluster
--   where
--     cast(substr(forecast_datetime, 12, 2) as bigint) = 10
)

select
  td_time_parse(t1.processing_date, 'jst') as time
  , t2.*
  , t3.week as week
  , t1.forecast_datetime
  , date_diff('week', cast(t1.processing_date as date),cast(substr(t1.forecast_datetime, 1, 10) as date)) as weeks_ahead
  , substr(t1.forecast_datetime, 1, 10) as business_day
  , td_time_format(td_date_trunc('week', td_time_parse(t1.forecast_datetime, 'jst'), 'jst'), 'YYYY-MM-dd', 'jst') as business_week
  , substr('月火水木金土日', dow(cast(substr(t1.forecast_datetime, 1, 10) as timestamp)), 1) as business_dow
  , cast(substr(t1.forecast_datetime, 12, 2) as bigint) as business_hour
  , round(if(t1.forecast_value * t3.coef<=0, 0, t1.forecast_value * t3.coef), 0) as forecast_treatment_value
  -- , case
  --     when cast(substr(t1.forecast_datetime, 12, 2) as bigint) >= 20 
  --       then round(if(t1.forecast_value * t3.coef<=0, 0, t1.forecast_value * if(t3.coef < t4.coef, t3.coef, t4.coef)), 0)
  --     else round(if(t1.forecast_value * t3.coef<=0, 0, t1.forecast_value * t3.coef), 0)
  --   end as forecast_treatment_value
from
  prep_forecast_by_cluster as t1
  left join prep_cluster_result as t2 on t1.processing_date = t2.processing_date and t1.cluster_id = t2.cluster_id
  inner join prep_rebate_coef as t3 on t1.processing_date = t3.processing_date and t2.mst_shop_id = t3.mst_shop_id and t1.business_hour = t3.business_hour and t1.week = t3.week
  -- left join adjust_rebate_coef as t4 on t3.processing_date = t4.processing_date and t3.mst_shop_id = t4.mst_shop_id and t3.week = t4.week
where
  t1.processing_date >= '2023-05-29'