with mst_bed_num as (
  select
    property_id as mst_shop_id
    , latest_bed_num
  from
    l1_core.property
)
, shop_master as (
  select
    id as mst_shop_id
    , no as mst_shop_no
    , name as mst_shop_name
  from
    l1_pos.mst_shops
)
, holiday_list as (
  select distinct
    td_time_format(td_time_parse(day, 'jst'), 'YYYY/MM/dd', 'jst') as business_day
  from
    l0_csv_upload.holiday_calendar
  where
    td_time_range(td_time_parse(day, 'jst'), '2021-12-28', null, 'jst')
)
, vtable_raw as (
  select
    processing_date
    , cluster_id
    , t1.mst_shop_id
    , mst_shop_no
    , mst_shop_name
    , t4.latest_bed_num
    , forecast_week
    , weeks_ahead - 1 as weeks_ahead_riraku
    , td_time_format(td_time_add(processing_date, '7d', 'jst'), 'YYYY-MM-dd', 'jst') as processing_date_riraku
    , t1.business_day
    , business_dow
    , if(t3.business_day is not null, '祝', business_dow) as business_dow_fixed
    , business_hour
    , forecast_value
    , loss_opps_fin_value
    , cast(culculate_work/60 as bigint) as time_slot
  from
    prep_join_all_with_lost_opps_55_3 as t1
    left join shop_master as t2 on t1.mst_shop_id = t2.mst_shop_id
    left join holiday_list as t3 on t1.business_day = t3.business_day
    left join mst_bed_num as t4 on t1.mst_shop_id = t4.mst_shop_id
  where
    weeks_ahead between 1 and 6
)

select
  td_time_parse(processing_date, 'jst') as time
  , processing_date
  , t1.mst_shop_id
  , mst_shop_no
  , mst_shop_name
  , latest_bed_num
  , forecast_week
  , weeks_ahead_riraku
  , processing_date_riraku
  , t1.business_day
  , t1.business_dow
  , t1.business_dow_fixed
  , t1.business_hour
  , if(time_slot > latest_bed_num, latest_bed_num, time_slot) as time_slot_restricted
  , if(time_slot > latest_bed_num, latest_bed_num, time_slot) as time_slot
  , case
      when forecast_value+loss_opps_fin_value < 30 then 0
      else cast(ceiling(forecast_value/60) as bigint)
    end as td1
  , case
      when (forecast_value+loss_opps_fin_value) < 20 then 0
      else cast(ceiling((forecast_value+loss_opps_fin_value)/60) as bigint) - if(forecast_value+loss_opps_fin_value < 30, 0, cast(ceiling(forecast_value/60) as bigint))
    end as td2
  , cast(time_slot as bigint) - if(forecast_value+loss_opps_fin_value < 20, 0, cast(ceiling((forecast_value+loss_opps_fin_value)/60) as bigint)) as td3
  , forecast_value
  , loss_opps_fin_value
from
  vtable_raw as t1
where
  weeks_ahead_riraku >= 0
