with mst_tp as (
  select
    therapist_id
    , therapist_no
  from
    _integration_datamart.mst_therapist
  where
    division = 0
)
, mst_shop as (
  select
    distinct
    property_id
    , shop_no
    , shop_name
  from
    _integration_datamart.mst_shop
  where
    status = '02'
)

, mst_datetime as (
  select
    distinct
    business_date
    , business_dow
  from
    _integration_datamart.mst_datetime
)

select
  td_time_parse(coalesce(send_datetime, t1.registered_datetime), 'jst') as time
  , t4.therapist_no as mstr__id
  , td_time_parse(coalesce(send_datetime, t1.registered_datetime), 'jst') as send_datetime
  , t5.shop_no
  , t5.shop_name
  , td_time_add(td_time_parse(t0.date, 'jst'), substr(t0.start_time, 1, 2)||'h') as timeslot_datetime
  , t6.business_dow as timeslot_dow
  , cast(substr(t0.start_time, 1, 2) as bigint) as timeslot_hour
  /* サジェスト種別 2025/11時点では、TD1、クエストのみ */
  , case
      when regexp_like(title, 'TD1') then 'TD1'
      else 'クエスト'
    end as suggest_type
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
inner join 
  mst_tp as t4
  on t0.therapist_id = t4.therapist_id
inner join 
  mst_shop as t5
  on t0.property_id = t5.property_id
inner join
  mst_datetime as t6
  on substr(t0.date, 1, 10) = t6.business_date