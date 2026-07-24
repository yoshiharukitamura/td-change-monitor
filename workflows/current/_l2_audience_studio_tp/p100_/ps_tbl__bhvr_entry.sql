with map_tp_shop as (
  select distinct
    therapist_no as mstr__id
    , shop_no as slot_shop_no
  from
    _integration_datamart.cls_time_slot_detail
  where
    td_time_range(time, td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-4w'), td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '1w'), 'jst')
)
, latest_timeslot as (
  select
    mst_shop_no as slot_shop_no
    , mst_shop_name as slot_shop_name
    , td_time_add(td_time_parse(business_day, 'jst'), cast(business_hour as varchar)||'h') as slot_datetime
    , business_dow_fixed as slot_dow
    , business_hour as slot_hour
    , time_slot as slot_count
    , td1 as slot_td1
    , td2 as slot_td2
    , td3 as slot_td3
  from
    _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
    inner join (
        select business_day, max(processing_date) as processing_date
        from _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
        group by business_day
      ) using (business_day, processing_date)
  where
    td_time_parse(forecast_week, 'jst') >= td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-52w')
)
, total_entry as (
  select
    shop_no as slot_shop_no
    , slot_from as slot_datetime
    , sum(entry_slot) as slot_total_entered
  from
    _integration_datamart.cls_time_slot_detail
  group by
    1,2
)
, tp_entry as (
  select
    therapist_no as mstr__id
    , shop_no as slot_shop_no
    , slot_from as slot_datetime
    , 'Yes' as slot_tp_entered
  from
    _integration_datamart.cls_time_slot_detail
)

select
  slot_datetime as time
  , mstr__id
  , slot_shop_no as timeslot_shop_no
  , slot_shop_name as timeslot_shop_name
  , slot_datetime as timeslot_datetime
  , slot_dow as timeslot_dow
  , slot_hour as timeslot_hour
  , slot_count as timeslot_count
  , slot_td1 as timeslot_td1
  , slot_td2 as timeslot_td2
  , slot_td3 as timeslot_td3
  , coalesce(slot_total_entered, 0) as timeslot_total_entry
  , greatest(slot_count - coalesce(slot_total_entered, 0), 0) as timeslot_total_shortage
  , coalesce(slot_tp_entered, 'No') as therapist_entry_flag
from
  latest_timeslot
  inner join map_tp_shop using (slot_shop_no)
  left join total_entry using (slot_shop_no, slot_datetime)
  left join tp_entry using (mstr__id, slot_shop_no, slot_datetime)
