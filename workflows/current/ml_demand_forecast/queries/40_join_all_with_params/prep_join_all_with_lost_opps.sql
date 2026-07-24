with last_process as (
  select
    max(processing_date) as processing_date
  from
    prep_join_all
  where
    processing_date = td_time_format(td_scheduled_time(), 'YYYY-MM-dd', 'jst')
)
, params as (
  select
    4 as key
    , 'D:取りこぼし' as case_num
    , 0.55 as target_utilization
    , 180 as upper_surplus_minute
    -- , 0.62 as target_utilization
    -- , 120 as upper_surplus_minute
    , 10 as bullish_rank_top_percent
    , -30 as bullish_minus_minute
    , 5 as bearish_rank_top_percent
    , 15 as bearish_plus_minute
)
, mst_bed_num as (
  select
    property_id as mst_shop_id
    , latest_bed_num
  from
    l1_core.property
)
, tmp as (
  select
    t1.time
    , t1.processing_date
    , cluster_id
    , weeks_ahead
    , business_week as forecast_week
    , business_day
    , t1.business_dow
    , t1.business_hour
    , t1.mst_shop_id
    , t3.latest_bed_num
    , result_timeslot_value as work_value
    , result_treatment_value as result_value
    , forecast_treatment_value as forecast_value
    , coalesce(t4.loss_opps_fin,0)*60 as loss_opps_fin_value
    , forecast_minus_avg_result
    , bullish_rank
    , bearish_rank
    , square_count
    , case_num
    , target_utilization
    , upper_surplus_minute
    , bullish_rank_top_percent
    , bullish_minus_minute
    , bearish_rank_top_percent
    , bearish_plus_minute
    , case
      when bullish_rank/square_count*100<=bullish_rank_top_percent
          and ceiling(((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)/target_utilization+bullish_minus_minute)/60)*60<=(forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)+upper_surplus_minute
        then if((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)=0, 0, ceiling(((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)/target_utilization+bullish_minus_minute)/60)*60)
      when bullish_rank/square_count*100<=bullish_rank_top_percent
          and ceiling(((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)/target_utilization+bullish_minus_minute)/60)*60>(forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)+upper_surplus_minute
        then if((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)=0, 0, floor(((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)+upper_surplus_minute)/60)*60)
      when bearish_rank/square_count*100<=bearish_rank_top_percent
        then if((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)=0, 0, ceiling(((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)/target_utilization+bearish_plus_minute)/60)*60)
      when ceiling((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)/target_utilization/60)*60<=(forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)+upper_surplus_minute
        then if((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)=0, 0, ceiling(((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)/target_utilization)/60)*60)
      when ceiling((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)/target_utilization/60)*60>(forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)+upper_surplus_minute
        then if((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)=0, 0, floor(((forecast_treatment_value+coalesce(t4.loss_opps_fin,0)*60)+upper_surplus_minute)/60)*60)
      else null
    end as culculate_work
    , if(result_timeslot_value>=180 and result_timeslot_value - result_treatment_value <= 60 and result_treatment_value*100/coalesce(result_timeslot_value,1)>=75, 60, 0) as missing_assumption
  from
    prep_join_all as t1
    left join params as t2 on t2.key > 0
    left join mst_bed_num as t3 on t1.mst_shop_id = t3.mst_shop_id
    left join prep_lost_opportunity as t4
      on t1.mst_shop_id = t4.mst_shop_id and t1.business_dow = t4.business_dow and t1.business_hour = t4.business_hour
    inner join last_process as t2 on t1.processing_date = t2.processing_date
  where
    td_time_range(t1.time, '2020-01-01', null, 'jst')
)

select
  time
  , processing_date
  , cluster_id
  , weeks_ahead
  , forecast_week
  , business_day
  , business_dow
  , business_hour
  , mst_shop_id
  , latest_bed_num
  , work_value
  , result_value
  , forecast_value
  , loss_opps_fin_value
  , forecast_minus_avg_result
  , bullish_rank
  , bearish_rank
  , square_count
  , case_num
  , target_utilization
  , upper_surplus_minute
  , bullish_rank_top_percent
  , bullish_minus_minute
  , bearish_rank_top_percent
  , bearish_plus_minute
  , culculate_work as culculate_work_raw
  , if(culculate_work<120, 120, coalesce(culculate_work, 0)) as culculate_work_min2
  , if(culculate_work<120, 120, if(coalesce(latest_bed_num*60, culculate_work) >= coalesce(culculate_work, 0), coalesce(culculate_work, 0), coalesce(latest_bed_num*60, culculate_work))) as culculate_work
  , missing_assumption
from
  tmp
