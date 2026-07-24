with shop_master as (
  select
    id as mst_shop_id
    , no as mst_shop_no
    , name as mst_shop_name
  from
    _l1_mysql_pos.mst_shops
)
, mst_bed_num as (
  select
    property_id as mst_shop_id
    , latest_bed_num
  from
    _l1_mysql_core.property
)
, dow_list as (
  select distinct
    business_day
    , business_dow
  from
    _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
)
, existing_master as (
  select distinct
    mst_shop_id
    , mst_shop_no
    , mst_shop_name
    , latest_bed_num
  from
    _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
  where
    time = td_date_trunc('week', td_scheduled_time(), 'jst')
)
, raw_spreadsheet_manual_linkage as (
  select
    td_time_string(td_date_trunc('week', td_scheduled_time(), 'jst'), 'd!', 'jst') as processing_date
    , property_id as mst_shop_id
    , substr(business_day, 1, 10) as business_day
    , cast(business_hour as bigint) as business_hour
    , time_slot
  from
    spreadsheet_manual_linkage
    cross join unnest(
      array['06', '07', '08', '09', '10', '11', '12', '13', '14', '15', '16', '17', '18', '19', '20', '21', '22', '23', '24', '25', '26', '27', '28', '29']
      , array[h06, h07, h08, h09, h10, h11, h12, h13, h14, h15, h16, h17, h18, h19, h20, h21, h22, h23, h24, h25, h26, h27, h28, h29]
    ) AS t(business_hour, time_slot)
  where
    time = td_scheduled_time()
    and td_time_range(td_time_parse(business_day, 'jst'), td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '7d', 'jst'), td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '49d', 'jst'), 'jst')
)
, prep_spreadsheet_manual_linkage as (
  select
    t1.mst_shop_id
    , coalesce(t1.mst_shop_no, t2.mst_shop_no) as mst_shop_no
    , coalesce(t1.mst_shop_name, t2.mst_shop_name) as mst_shop_name
    , coalesce(t1.latest_bed_num, t3.latest_bed_num) as latest_bed_num
    , td_time_string(td_date_trunc('week', td_time_parse(t1.business_day, 'jst'), 'jst'), 'd!', 'jst') as forecast_week
    , date_diff('week', cast(td_time_string(td_time_add(t1.processing_date, '7d', 'jst'), 'd!', 'jst') as date), cast(td_time_string(td_date_trunc('week', td_time_parse(t1.business_day, 'jst'), 'jst'), 'd!', 'jst') as date)) as weeks_ahead_riraku
    , td_time_string(td_time_add(t1.processing_date, '7d', 'jst'), 'd!', 'jst') as processing_date_riraku
    , t1.business_day
    , t1.business_hour
    , t4.business_dow
    , t1.time_slot
  from (
      select
        *
      from
        raw_spreadsheet_manual_linkage
        left join existing_master using (mst_shop_id)
    ) as t1
    left join shop_master as t2 on t1.mst_shop_id = t2.mst_shop_id
    left join mst_bed_num as t3 on t1.mst_shop_id = t3.mst_shop_id
    left join dow_list as t4 on t1.business_day = t4.business_day
)
, vtable_target as (
  select
    *
  from
    _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
  where
    time = td_date_trunc('week', td_scheduled_time(), 'jst')
)

select
  coalesce(t1.time, td_date_trunc('week', td_scheduled_time(), 'jst')) as time
  , coalesce(t1.processing_date, td_time_string(td_date_trunc('week', td_scheduled_time(), 'jst'), 'd!', 'jst')) as processing_date
  , if(t2.mst_shop_id is null, 0, 1) is_manual_fixed
  , coalesce(t1.mst_shop_id, t2.mst_shop_id) as mst_shop_id
  , coalesce(t1.mst_shop_no, t2.mst_shop_no) as mst_shop_no
  , coalesce(t1.mst_shop_name, t2.mst_shop_name) as mst_shop_name
  , coalesce(t1.latest_bed_num, t2.latest_bed_num) as latest_bed_num
  , coalesce(t1.forecast_week, t2.forecast_week) as forecast_week
  , coalesce(t1.weeks_ahead_riraku, t2.weeks_ahead_riraku) as weeks_ahead_riraku
  , coalesce(t1.processing_date_riraku, t2.processing_date_riraku) as processing_date_riraku
  , coalesce(t1.business_day, t2.business_day) as business_day
  , coalesce(t1.business_dow, t2.business_dow) as business_dow
  , t1.business_dow_fixed
  , coalesce(t1.business_hour, t2.business_hour) as business_hour
  , coalesce(t2.time_slot, t1.time_slot_restricted) as time_slot_restricted
  , coalesce(t2.time_slot, t1.time_slot) as time_slot
  , if(t2.time_slot is null, t1.td1, if(t2.time_slot>coalesce(t1.td1, 0), coalesce(t1.td1, 0), t2.time_slot)) as td1
  -- , if(t2.time_slot is null, t1.td2, if(t2.time_slot>t1.td1+t1.td2, t1.td2, if(t2.time_slot-t1.td1>0, t2.time_slot-t1.td1, 0))) as td2
  , case
      when t3.span = '2/10（月）～2/23（日）' and coalesce(t1.business_day, t2.business_day) between '2025-02-10' and '2025-02-23' then 0
      when t3.span = '2/15（土）、2/16（日）、2/22（土）、2/23（日）' and coalesce(t1.business_day, t2.business_day) between '2025-02-10' and '2025-02-23'
        and coalesce(t1.business_dow, t2.business_dow) in ('土', '日') then 0
      else if(t2.time_slot is null, t1.td2, if(t2.time_slot>coalesce(t1.td1, 0)+coalesce(t1.td2, 0), coalesce(t1.td2, 0), if(t2.time_slot-t1.td1>0, t2.time_slot-t1.td1, 0)))
    end as td2
  -- , if(t2.time_slot is null, t1.td3, if(t2.time_slot>t1.td1+t1.td2+t1.td3, t1.td3, if(t2.time_slot-t1.td1-t1.td2>0, t2.time_slot-t1.td1-t1.td2, 0))) as td3
  , case
      when t3.span = '2/10（月）～2/23（日）' and coalesce(t1.business_day, t2.business_day) between '2025-02-10' and '2025-02-23' then td2+td3
      when t3.span = '2/15（土）、2/16（日）、2/22（土）、2/23（日）' and coalesce(t1.business_day, t2.business_day) between '2025-02-10' and '2025-02-23'
        and coalesce(t1.business_dow, t2.business_dow) in ('土', '日') then td2+td3
      else if(t2.time_slot is null, t1.td3, if(t2.time_slot>coalesce(t1.td1, 0)+coalesce(t1.td2, 0)+coalesce(t1.td3, 0), coalesce(t1.td3, 0), if(t2.time_slot-t1.td1-t1.td2>0, t2.time_slot-t1.td1-t1.td2, 0)))
    end as td3
  , t1.forecast_value
  , t1.loss_opps_fin_value
from
  vtable_target as t1
  full join prep_spreadsheet_manual_linkage as t2
    on
      t1.mst_shop_id = t2.mst_shop_id
      and t1.business_day = t2.business_day
      and t1.business_hour = t2.business_hour
  left join tmp_250205 as t3 on t1.mst_shop_id = t3.mst_shop_id
