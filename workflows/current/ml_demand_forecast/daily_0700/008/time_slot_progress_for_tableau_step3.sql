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
    t1.business_week
    , t2.flag
    , t2.offset_diff
    , shop_id
    , business_date
    , business_hour
    , td1
    , td2
    , td12
    , td3
    , td123
  from
    l2_shop_db_dev.time_slot_history as t1
    inner join (
        select distinct
          business_week
          , flag
          , offset_diff
        from
          l2_shop_db_dev.time_slot_progress_prep
        where
          flag != '01_week_offset'        
      ) as t2 on t1.business_week = t2.business_week
  where
    t1.offset_diff = 0
)
, data_agg as (
  select
    business_week
    , flag
    , processing_week
    , offset_diff
    , shop_id
    , business_date
    , business_hour
    , sum(time_slot) as time_slot
  from
    l2_shop_db_dev.time_slot_progress_prep
  where
    flag != '01_week_offset'
  group by
    business_week
    , flag
    , processing_week
    , offset_diff
    , shop_id
    , business_date
    , business_hour
)

select
  td_time_parse(business_week, 'jst') as time
  , *
  , 'TD123 Weekly 2' as data_type
  , case
      when flag = '02_quest' and offset_diff = 0 then 'クエスト発動'
      when flag = '03_date_offset' and offset_diff = 3 then '-3d開始'
      when flag = '03_date_offset' and offset_diff = 2 then '-2d開始'
      when flag = '03_date_offset' and offset_diff = 1 then '-1d開始'
      when flag = '03_date_offset' and offset_diff = 0 then '当日0時'
      when flag = '04_hour_offset' and offset_diff = 3 then '-3h開始'
      when flag = '04_hour_offset' and offset_diff = 2 then '-2h開始'
      when flag = '04_hour_offset' and offset_diff = 1 then '-1h開始'
      when flag = '04_hour_offset' and offset_diff = 0 then '施術開始'
      when flag = '05_confirmed' and offset_diff = -1 then '最終受注枠'
    end as flag_name
  , case
      when regexp_like(flag, '01_week_offset|02_quest|05_confirmed') then td_time_string(td_time_add(business_week, cast( - offset_diff as varchar)||'w', 'jst'), 'd!', 'jst')
      else business_week
      -- when regexp_like(flag, '03_date_offset') then td_time_string(td_time_add(business_week, cast(offset_diff as varchar)||'d', 'jst'), 'd!', 'jst')
      -- when regexp_like(flag, '04_hour_offset') then td_time_string(td_time_add(business_week, cast(offset_diff as varchar)||'d', 'jst'), 'd!', 'jst')
    end as flag_date
  , if(td1<=coalesce(time_slot,0), td1, coalesce(time_slot,0)) as accept_td1
  , if(td12<=coalesce(time_slot,0), td12, coalesce(time_slot,0)) as accept_td12
  , if(td123<=coalesce(time_slot,0), td123, coalesce(time_slot,0)) as accept_td123
  , if(td1<=coalesce(time_slot,0), 0, td1 - coalesce(time_slot,0)) as remain_td1
  , if(td12<=coalesce(time_slot,0), 0, td12 - coalesce(time_slot,0)) as remain_td12
  , if(td123<=coalesce(time_slot,0), 0, td123 - coalesce(time_slot,0)) as remain_td123
from
  time_slot_master
  left join data_agg using (business_week, flag, offset_diff, shop_id, business_date, business_hour)
  left join shop_master using (shop_id)
  left join quest_stop_master_shop using (business_week, shop_id)

