with prep_td_timeslot as (
  select
    business_day as business_date
    , cluster_id
    , cast(null as bigint) as therapist_id
    , mst_shop_id as property_id
    , business_hour
    , time_slot as td_time_slot
    , td1
    , td2
    , td3
    , forecast_value
    , loss_opps_fin_value
  from
    _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
    inner join (select business_day, min(weeks_ahead_riraku) as weeks_ahead_riraku from _l2_demand_forecast_gcp.fin_timeslot_raw_vtable group by 1) using (business_day, weeks_ahead_riraku)
    inner join (select distinct property_id as mst_shop_id from _integration_datamart.mst_shop where status_name = '営業中') using (mst_shop_id)
)
, prep_timeslot as (
  select
    property_id
    , business_date
    , business_hour
    , sum(entry_slot) as entry_slot
  from
    _integration_datamart.cls_time_slot_detail
  group by
    1,2,3
)
, prep_order as (
  select
    property_id
    , business_date
    , business_hour
    , sum(treatment_minutes_in_hour) as treatment_minutes
  from
    _integration_datamart.cls_order_detail
  where
    coalesce(product_name, 'もみほぐし') like '%もみほぐし%'
  group by
    1,2,3    
)

select
  td_time_parse(business_date, 'jst') as time
  , property_id
  , property_id as mst_shop_id
  , td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst') as business_week
  , substr('月火水木金土日', dow(cast(business_date as date)), 1) as business_dow
  , business_date
  , business_hour
  , td_time_slot
  , td1
  , td2
  , td3
  , forecast_value
  , loss_opps_fin_value
  , entry_slot
  , treatment_minutes
  , sum(entry_slot) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 4 preceding and 1 preceding)
    / sum(td_time_slot) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 4 preceding and 1 preceding) as sufficiency_past_4week
  , sum(entry_slot) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 8 preceding and 1 preceding)
    / sum(td_time_slot) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 8 preceding and 1 preceding) as sufficiency_past_8week
  , sum(entry_slot) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 15 preceding and 1 preceding)
    / sum(td_time_slot) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 15 preceding and 1 preceding) as sufficiency_past_15week
  , case
      when sum(entry_slot) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 4 preceding and 1 preceding) > 0
      then
          sum(treatment_minutes) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 4 preceding and 1 preceding) /60
          / sum(entry_slot) over (partition by dow(cast(business_date as date)), business_hour, property_id order by business_date rows between 4 preceding and 1 preceding)
      end as utilization
from
  prep_td_timeslot
  left join prep_timeslot using (property_id, business_date, business_hour)
  left join prep_order using (property_id, business_date, business_hour)
