with time_slot_master as (
  select
    business_week
    , shop_id
    , business_date
    , business_hour
    , td1
    , td2
    , td12
    , td3
    , td123
  from
    l2_shop_db_dev.time_slot_history
  where
    offset_diff = 0
)
, holiday_list as (
  select distinct
    td_time_string(td_time_parse(holiday_date, 'jst'), 'd!', 'jst') as business_date
    , 1 as is_holiday
  from
    _l1_mysql_core.holiday
)
, latest_shop_master as (
  select
    shop_id
    , if(cast(split(start_time, ':')[1] as bigint)<10, '0'||replace(start_time, ':', ''), replace(start_time, ':', '')) as start_time
    , if(cast(split(end_time, ':')[1] as bigint)<10, '0'||replace(end_time, ':', ''), replace(end_time, ':', '')) as end_time
  from
    l2_demand_forecast_auto.spreadsheets_shop_master
  where
    time = td_scheduled_time()
)
, quest_stop_master_shop as (
  select distinct
    td_time_string(td_time_parse(business_week, 'jst'), 'd!', 'jst') as business_week
    , property_id as shop_id
    , min(type) as q_stop_type_shop
  from
    l2_demand_forecast_auto.spreadsheets_quest_stop_list_shop
  where
    time = td_scheduled_time()
  group by
    1,2
)
, data_agg as (
  select
    business_week
    , shop_id
    , business_date
    , business_hour
    , cast(sum(time_slot) as bigint) as time_slot
  from
    l2_shop_db_dev.time_slot_progress_prep
  where
    flag = '02_quest'
  group by
    business_week
    , shop_id
    , business_date
    , business_hour
)
, data_prep as (
  select
    td_time_parse(business_week, 'jst') as time
    , business_week
    , business_date
    , business_hour
    , shop_id as property_id
    , business_date as date
    , if(business_hour<10, '0'||cast(business_hour as varchar), cast(business_hour as varchar))||'00' as start_time
    , if(business_hour+1<10, '0'||cast(business_hour+1 as varchar), cast(business_hour+1 as varchar))||'00' as end_time
    , td_time_string(td_time_add(td_time_add(business_week, '-3d', 'jst'), '18h', 'jst'), 's!', 'jst') as quest_publication_period_start_datetime
    -- , td_time_string(td_time_add(business_week, '7d', 'jst'), 's!', 'jst') as quest_publication_period_end_datetime
    , td_time_string(td_time_add(business_date, '6h', 'jst'), 's!', 'jst') as quest_publication_period_end_datetime
    , td1 as td1_raw
    , td2 as td2_raw
    , td3 as td3_raw
    , time_slot
    , cast(if(td1 > coalesce(time_slot,0), td1 - coalesce(time_slot,0), 0) as bigint) as td1
    , cast(case
        when td12 > coalesce(time_slot,0) and td1 > coalesce(time_slot,0) then td2
        when td12 > coalesce(time_slot,0) then td12 - coalesce(time_slot,0)
        else 0
      end as bigint) as td2
    , cast(case
        when td123 > coalesce(time_slot,0) and td12 > coalesce(time_slot,0) then td3
        when td123 > coalesce(time_slot,0) then td123 - coalesce(time_slot,0)
        else 0
      end as bigint) as td3
    , if(td1<=coalesce(time_slot,0), td1, coalesce(time_slot,0)) as accept_td1
    , if(td12<=coalesce(time_slot,0), td12, coalesce(time_slot,0)) as accept_td12
    , if(td123<=coalesce(time_slot,0), td123, coalesce(time_slot,0)) as accept_td123
    , if(td1<=coalesce(time_slot,0), 0, td1 - coalesce(time_slot,0)) as remain_td1
    , if(td12<=coalesce(time_slot,0), 0, td12 - coalesce(time_slot,0)) as remain_td12
    , if(td123<=coalesce(time_slot,0), 0, td123 - coalesce(time_slot,0)) as remain_td123
    , q_stop_type_shop
    , case q_stop_type_shop
        when '全停止' then 1
        when '土日停止' then if(dow(cast(business_date as date)) >= 6 or is_holiday = 1, 1, 0)
        else 0
      end as is_excluded
  from
    time_slot_master
    left join data_agg using (business_week, shop_id, business_date, business_hour)
    left join quest_stop_master_shop using (business_week, shop_id)
    left join holiday_list using (business_date)
    left join latest_shop_master using (shop_id)
  where
    td_time_parse(business_week, 'jst') = td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '7d', 'jst')
    and if(business_hour<10, '0'||cast(business_hour as varchar), cast(business_hour as varchar))||'00' >= start_time
    and if(business_hour+1<10, '0'||cast(business_hour+1 as varchar), cast(business_hour+1 as varchar))||'00' < end_time
)
, data_fin as (
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
    data_prep
    cross join unnest (
      sequence(1, td1, 1)
    ) as t(val)
  where
    td1 > 0
    and is_excluded = 0

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
    data_prep
    cross join unnest (
      sequence(1, td2, 1)
    ) as t(val)
  where
    td2 > 0
    and is_excluded = 0

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
    data_prep
    cross join unnest (
      sequence(1, td3, 1)
    ) as t(val)
  where
    td3 > 0
    and is_excluded = 0
)

select
  td_scheduled_time() as time
  , property_id
  , date
  , start_time
  , end_time
  , quest_publication_period_start_datetime
  , quest_publication_period_end_datetime
  , quest_reward
  , indication_order
  , quest_time_slot_type
  , '' as quest_entry_possible_therapist_no
from
  data_fin
