with tp_info as (
  select
    therapist_id
    , therapist_no
    , therapist_name
    , division
    , gender
    , age
    , hope_property_id_1
    , hope_property_id_2
    , work_saturday
    , work_sunday
    , work_holiday
    , week_days
    , timezone
  from
    _integration_datamart.mst_therapist
  where
    division = 0
)
, shop_info as (
  select
    property_id
    , shop_no
    , status
    , status_name
    , business_start_time
    , business_end_time
    , latest_bed_num
    , pref_name
    , area_name
    , market_population_1km
    , market_population_3km
  from
    _integration_datamart.mst_shop
  where
    status = '02'
)

select
  td_time_parse(substr(t0.date, 1, 10), 'jst') as time
  , td_time_string(td_time_parse(substr(t0.date, 1, 10), 'jst'), 's!', 'jst') as time_fmt
  , 'business_date' as time_means
  , send_datetime
  , t0.therapist_id
  , t0.property_id
  , substr(t0.date, 1, 10) as business_date
  , cast(substr(t0.start_time, 1, 2) as bigint) as business_hour
  , td_time_add(td_time_parse(t0.date, 'jst'), substr(t0.start_time, 1, 2)||'h') as slot_from
  , td_time_add(td_time_parse(t0.date, 'jst'), substr(t0.end_time, 1, 2)||'h') as slot_to
  /* サジェスト種別 2025/11時点では、TD1、クエストのみ */
  , case
      when regexp_like(title, 'TD1') then 'TD1'
      else 'クエスト'
    end as suggest_type
  , case
      when t4.time_slot_detail_id is null then null
      when substr(t4.end_time, 3, 2) = '30' then 0.5
      when substr(t4.end_time, 3, 2) = '00' then 1.0
    end as entry_slot
  , t5.therapist_no
  , t5.therapist_name
  , t5.division
  , t5.gender
  , t5.age
  , t5.hope_property_id_1
  , t5.hope_property_id_2
  , t5.work_saturday
  , t5.work_sunday
  , t5.work_holiday
  , t5.week_days
  , t5.timezone
  , t6.shop_no
  , t6.status
  , t6.status_name
  , t6.business_start_time
  , t6.business_end_time
  , t6.latest_bed_num
  , t6.pref_name
  , t6.area_name
  , t6.market_population_1km
  , t6.market_population_3km
from 
  _l1_mysql_core.suggest_time_slot_detail_therapist as t0
left join
  _l1_mysql_core.suggest_entry_notification_history as t1
  on t0.suggest_entry_notification_history_id = t1.suggest_entry_notification_history_id
left join
  _l1_mysql_core.suggest_entry_notification as t2
  on t1.suggest_entry_notification_id = t2.suggest_entry_notification_id
left join
  _l1_mysql_core.suggest_time_slot_detail as t3
  on t0.date = t3.date
     and t0.property_id = t3.property_id
     and t0.start_time = t3.start_time
     and t0.therapist_id = t3.therapist_id
left join
  _l1_mysql_core.time_slot_detail as t4
  on t3.time_slot_detail_id = t4.time_slot_detail_id
inner join 
  tp_info as t5
  on t0.therapist_id = t5.therapist_id
inner join 
  shop_info as t6
  on t0.property_id = t6.property_id
where
  t0.read_flag = 1 /* サジェストの閲覧を分母とする */