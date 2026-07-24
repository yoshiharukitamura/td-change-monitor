with entry_ts as (
  select
    therapist_no
    , shop_no
    , shop_name
    , business_dow
    , holiday_type
    , business_hour
    , time_slot
    , facilities_usage_minuites
    , final_entry_minuites
    , treatment_minuites
  from
    _integration_datamart.cls_time_slot_integrated
    left join (select distinct shop_no, shop_name from _integration_datamart.mst_shop)
    using (shop_no)
)

select
  td_time_parse(time_slot, 'jst') as time
  , therapist_no as mstr__id
  , shop_no
  , shop_name
  , td_time_parse(time_slot, 'jst') as timeslot_datetime
  , business_dow as timeslot_dow
  , business_hour as timeslot_hour
  , facilities_usage_minuites
  , final_entry_minuites
  , treatment_minuites
from
  entry_ts