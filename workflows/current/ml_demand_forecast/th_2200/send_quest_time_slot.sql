select
  property_id
  , date
  , start_time
  , end_time
  , quest_publication_period_start_datetime
  , quest_publication_period_end_datetime
  , quest_reward
  , indication_order
  , quest_time_slot_type
  , quest_entry_possible_therapist_no
from
  l2_demand_forecast_auto.quest_time_slot
where
  time = td_scheduled_time()
order by
  property_id
  , date
  , start_time
  , end_time
  , quest_publication_period_start_datetime
  , quest_publication_period_end_datetime
  , quest_reward
  , indication_order
  , quest_time_slot_type
  , quest_entry_possible_therapist_no
