with shop_master as (
  select
    id as shop_id
    , no as shop_no
    , name as shop_name
  from
    _l0_mysql_pos.mst_shops
)
, quest_stop_master_shop as (
  select distinct
    td_time_string(td_time_parse(business_week, 'jst'), 'd!', 'jst') as business_week
    , property_id as shop_id
    , min(type) as q_stop_type_shop
  from
    l2_demand_forecast_auto.spreadsheets_quest_stop_list_shop
  group by
    1,2
)
, time_slot_master as (
  select
    business_week
    , processing_week
    , offset_diff
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
    offset_diff > 0
)
, data_agg as (
  select
    business_week
    , processing_week
    , shop_id
    , business_date
    , business_hour
    , sum(time_slot) as time_slot
  from
    l2_shop_db_dev.time_slot_progress_prep
  where
    flag = '01_week_offset'
  group by
    business_week
    , processing_week
    , shop_id
    , business_date
    , business_hour
)

select
  td_time_parse(business_week, 'jst') as time
  , *
  , 'TD123 Weekly 1' as data_type
  , case
      when offset_diff = 5 then '-5w開始'
      when offset_diff = 4 then '-4w開始'
      when offset_diff = 3 then '-3w開始'
      when offset_diff = 2 then '-2w開始'
      when offset_diff = 1 then '-1w開始'
    end as flag_name
  , td_time_string(td_time_add(business_week, cast( - offset_diff as varchar)||'w', 'jst'), 'd!', 'jst') as flag_date
  , if(td1<=coalesce(time_slot,0), td1, coalesce(time_slot,0)) as accept_td1
  , if(td12<=coalesce(time_slot,0), td12, coalesce(time_slot,0)) as accept_td12
  , if(td123<=coalesce(time_slot,0), td123, coalesce(time_slot,0)) as accept_td123
  , if(td1<=coalesce(time_slot,0), 0, td1 - coalesce(time_slot,0)) as remain_td1
  , if(td12<=coalesce(time_slot,0), 0, td12 - coalesce(time_slot,0)) as remain_td12
  , if(td123<=coalesce(time_slot,0), 0, td123 - coalesce(time_slot,0)) as remain_td123
from
  time_slot_master
  left join data_agg using (business_week, processing_week, shop_id, business_date, business_hour)
  left join shop_master using (shop_id)
  left join quest_stop_master_shop using (business_week, shop_id)
