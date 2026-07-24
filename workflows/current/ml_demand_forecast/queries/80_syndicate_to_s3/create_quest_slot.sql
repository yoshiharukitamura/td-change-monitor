with prep as (
  select
    mst_shop_id as property_id
    , business_day as date
    -- , business_hour
    , if(business_hour<10, '0'||cast(business_hour as varchar), cast(business_hour as varchar))||'00' as start_time
    , if(business_hour+1<10, '0'||cast(business_hour+1 as varchar), cast(business_hour+1 as varchar))||'00' as end_time
    -- , forecast_week
    , td_time_string(td_time_add(td_time_add(forecast_week, '-3d', 'jst'), '18h', 'jst'), 's!', 'jst') as quest_publication_period_start_datetime
    , td_time_string(td_time_add(forecast_week, '7d', 'jst'), 's!', 'jst') as quest_publication_period_end_datetime
    -- , 1 as quest_reward
    -- , 1 as indication_order
    -- , 1 as quest_time_slot_type
    , td1
    , td2
    , td3
  from
    fin_timeslot_raw_vtable_fixed
  where
    time = td_date_trunc('week', td_scheduled_time(), 'jst')
    and forecast_week = td_time_string(td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '7d', 'jst'), 'd!', 'jst')
)
, fin as (
  select
    property_id
    , date
    , start_time
    , end_time
    , quest_publication_period_start_datetime
    , quest_publication_period_end_datetime
    , td1 as check
    , val
    , 500 as quest_reward
    , 10 as indication_order
    , 'TD1' as quest_time_slot_type
  from
    prep
    cross join unnest (
      sequence(1, td1, 1)
    ) as t(val)
  where
    td1 > 0

  union all

  select
    property_id
    , date
    , start_time
    , end_time
    , quest_publication_period_start_datetime
    , quest_publication_period_end_datetime
    , td2 as check
    , val
    , 300 as quest_reward
    , 20 as indication_order
    , 'TD2' as quest_time_slot_type
  from
    prep
    cross join unnest (
      sequence(1, td2, 1)
    ) as t(val)
  where
    td2 > 0

  union all

  select
    property_id
    , date
    , start_time
    , end_time
    , quest_publication_period_start_datetime
    , quest_publication_period_end_datetime
    , td3 as check
    , val
    , 100 as quest_reward
    , 30 as indication_order
    , 'TD3' as quest_time_slot_type
  from
    prep
    cross join unnest (
      sequence(1, td3, 1)
    ) as t(val)
  where
    td3 > 0
)

select
  property_id
  , date
  , start_time
  , end_time
  , quest_publication_period_start_datetime
  , quest_publication_period_end_datetime
  -- , td3 as check
  -- , val
  , quest_reward
  , indication_order
  , quest_time_slot_type
  , '' as quest_entry_possible_therapist_no
from
  fin
order by
  property_id
  , date
  , start_time
  , end_time
  , quest_publication_period_start_datetime
  , quest_publication_period_end_datetime
  , quest_time_slot_type
  , val
