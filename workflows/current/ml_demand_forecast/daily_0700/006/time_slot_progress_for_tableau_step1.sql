with shop_master as (
  select
    id as shop_id
    , no as shop_no
    , name as shop_name
  from
    _l0_mysql_pos.mst_shops
)
, therapist_master as (
  select
    therapist_id
    , therapist_no
    , processing_week
    , therapist_rank_class
  from
    l2_shop_db_dev.therapist_rank_class_weekly
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
, quest_stop_master_tp as (
  select distinct
    td_time_string(td_time_parse(target_week, 'jst'), 'd!', 'jst') as business_week
    , therapist_no
    , 'TP停止' as q_stop_type_tp
    , match_hour
    , pomp_hour
  from
    l2_demand_forecast_auto.spreadsheets_quest_stop_list
)
, data_agg as (
  select
    business_week
    , flag
    , processing_week
    , offset_diff
    , shop_id
    , therapist_id
    , sum(time_slot) as time_slot
  from
    l2_shop_db_dev.time_slot_progress_prep
  group by
    business_week
    , flag
    , processing_week
    , offset_diff
    , shop_id
    , therapist_id
)

select
  td_time_parse(business_week, 'jst') as time
  , *
  , 'TP Weekly' as data_type
  , case
      when flag = '01_week_offset' and offset_diff = 4 then '-4w開始'
      when flag = '01_week_offset' and offset_diff = 3 then '-3w開始'
      when flag = '01_week_offset' and offset_diff = 2 then '-2w開始'
      when flag = '01_week_offset' and offset_diff = 1 then '-1w開始'
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
from
  data_agg
  left join shop_master using (shop_id)
  left join therapist_master using (therapist_id, processing_week)
  left join quest_stop_master_shop using (business_week, shop_id)
  left join quest_stop_master_tp using (business_week, therapist_no)
