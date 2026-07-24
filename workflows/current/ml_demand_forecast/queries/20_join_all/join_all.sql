with join_table as (
  select
    td_time_parse(t1.processing_date, 'jst') as time
    , t1.processing_date
    , t1.weeks_ahead
    , t1.mst_shop_id
    , t1.forecast_datetime as business_datetime
    , t1.business_week
    , t1.business_day
    , t1.business_dow
    , t1.business_hour
    , t1.cluster_id
    , t1.forecast_treatment_value
    , t2.result_treatment_value
    , t3.avg_result_treatment_value
    , t4.result_timeslot_value
    , t5.avg_result_timeslot_value
    , if(t1.forecast_treatment_value is null, null, t1.forecast_treatment_value - coalesce(t3.avg_result_treatment_value, 0)) as forecast_minus_avg_result
  from
    prep_forecast_treatment as t1
    left join prep_result_treatment as t2
      on
        t1.mst_shop_id = t2.mst_shop_id
        and t1.forecast_datetime = t2.result_datetime
    left join prep_result_treatment as t3
      on
        t1.mst_shop_id = t3.mst_shop_id
        and t1.processing_date = t3.processing_date
        and t1.business_dow = t3.business_dow
        and t1.business_hour = t3.business_hour
    left join prep_result_timeslot as t4
      on
        t1.mst_shop_id = t4.mst_shop_id
        and t1.forecast_datetime = t4.result_datetime
    left join prep_result_timeslot as t5
      on
        t1.mst_shop_id = t5.mst_shop_id
        and t1.processing_date = t5.processing_date
        and t1.business_dow = t5.business_dow
        and t1.business_hour = t5.business_hour
)

select
  *
  , row_number() over (partition by processing_date, cluster_id order by forecast_minus_avg_result desc) as bullish_rank
  , row_number() over (partition by processing_date, cluster_id order by forecast_minus_avg_result) as bearish_rank
  , count(1) over (partition by processing_date, cluster_id) as square_count
from
  join_table
