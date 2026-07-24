-- drop table if exists l2_tp_suggest.suggest_rawdata_v2;
-- create table l2_tp_suggest.suggest_rawdata_v2 as
delete from l2_tp_suggest.suggest_rawdata_v2 where time = td_date_trunc('day', td_scheduled_time(), 'jst');
insert into l2_tp_suggest.suggest_rawdata_v2
with available_timeslot as (
  select
    property_id
    , cast(shop_no as bigint) as shop_no
    , shop_name
    , business_date
    , td_time_string(td_time_add(business_date, cast(business_hour as varchar)||'h', 'jst'), 's!', 'jst') as business_datetime
    , substr(business_date, 6, 2) as business_month
    , substr(business_date, 9, 2) as business_day
    , td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , business_dow
    , business_hour
    , td1
    , td2
    , td3
    , entry_slot
    , if(coalesce(entry_slot, 0) < td1, 'yes', null) as not_enough_td1
    , if(coalesce(entry_slot, 0) < td1 + td2, 'yes', null) as not_enough_td2
    , if(coalesce(entry_slot, 0) < td1 + td2 + td3, 'yes', null) as not_enough_td3
    , lag(utilization) over (partition by property_id, business_dow, business_hour order by business_week) as last_week_util
  from
    l2_tp_suggest.cls_sufficiency -- 現行モデルのテーブル
    left join (
        select
          property_id, shop_no, shop_name
          , cast(substr(business_start_time, 1, 2) as double) + if(substr(business_start_time, 4, 2) = '30', 0.5, 0.0) as business_start_time
          , cast(substr(business_end_time, 1, 2) as double) + if(substr(business_end_time, 4, 2) = '30', 0.5, 0.0) as business_end_time
        from
          _integration_datamart.mst_shop
      ) using (property_id)
  where
    td_time_parse(business_date, 'jst') >= td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-7d', 'jst')
    and coalesce(entry_slot, 0) < (td1 + td2 + td3)
    and cast(business_hour as double) between business_start_time and (business_end_time - 1.0)
)
, tp_entry as (
  select
    property_id
    , therapist_id
    , business_date
    , td_time_string(min(td_time_add(business_date, cast(business_hour as varchar)||'h', 'jst')), 's!', 'jst') as entry_from
    , td_time_string(max(td_time_add(business_date, cast(business_hour as varchar)||'h', 'jst')), 's!', 'jst') as entry_to
    , count(1) as todays_entry_count
  from
    l2_tp_suggest.cls_time_slot_detail
  where
    td_time_parse(business_date, 'jst') >= td_date_trunc('day', td_scheduled_time(), 'jst')
  group by
    1,2,3
)
, tp_entry_last_week as (
  select
    property_id
    , therapist_id
    , td_time_string(td_time_add(business_date, '7d', 'jst'), 'd!', 'jst') as business_date
    , td_time_string(min(td_time_add(td_time_add(business_date, '7d', 'jst'), cast(business_hour as varchar)||'h', 'jst')), 's!', 'jst') as entry_from_lw
    , td_time_string(max(td_time_add(td_time_add(business_date, '7d', 'jst'), cast(business_hour as varchar)||'h', 'jst')), 's!', 'jst') as entry_to_lw
    , count(1) as todays_entry_count_lw
  from
    l2_tp_suggest.cls_time_slot_detail
  where
    td_time_parse(business_date, 'jst') >= td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-7d')
  group by
    1,2,3
)
, tp_order_last_week as (
  select
    property_id
    , therapist_id
    , td_time_string(td_time_add(business_date, '7d'), 'd!', 'jst') as business_date
    , business_hour
    , least(sum(treatment_minutes_in_hour), 60) as treatment_minutes_in_hour_lw
  from
    _integration_datamart.cls_order_detail
  where
    td_time_parse(business_date, 'jst') >= td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-7d')
    and order_detail_id_seq = 1
  group by
    1,2,3,4
)
, available_quest_1 as (
  select distinct
    quest_time_slot_id
    , property_id
    , substr(date, 1, 10) as business_date
    , td_time_string(td_date_trunc('week', td_time_parse(date, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , cast(substr(start_time, 1, 2) as bigint) as business_hour
    , quest_time_slot_type as quest_time_slot_type_1
  from
    l2_tp_suggest.quest_time_slot
  where
    time = td_date_trunc('day', td_scheduled_time(), 'jst')
    and deleted = 0
    and therapist_id is null
    and quest_entry_possible_therapist_no is null
)
, available_quest_2 as (
  select distinct
    quest_time_slot_id
    , property_id
    , substr(date, 1, 10) as business_date
    , td_time_string(td_date_trunc('week', td_time_parse(date, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , cast(substr(start_time, 1, 2) as bigint) as business_hour
    , quest_time_slot_type
    , quest_entry_possible_therapist_no
    , therapist_no
    , tpid as therapist_id
  from
    l2_tp_suggest.quest_time_slot
    cross join unnest (
      split(quest_entry_possible_therapist_no, ':')
    ) as t(therapist_no)
    left join (select therapist_no, therapist_id as tpid from _integration_datamart.mst_therapist) using (therapist_no)
  where
    time = td_date_trunc('day', td_scheduled_time(), 'jst')
    and td_time_parse(substr(date, 1, 10), 'jst') >= td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-7d', 'jst')
    and deleted = 0
    and therapist_id is null
    and quest_entry_possible_therapist_no is not null
)

select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , property_id
  , shop_no
  , shop_name
  , business_datetime
  , business_week
  , business_date
  , business_month
  , business_day
  , business_dow
  , business_hour
  , td1
  , td2
  , td3
  , entry_slot
  , not_enough_td1
  , not_enough_td2
  , not_enough_td3
  , last_week_util
  , coalesce(quest_time_slot_type_2, quest_time_slot_type_1) as quest_time_slot_type
  , therapist_id
  , therapist_no
  , professional_name
  , email
  , entry_from
  , entry_to
  , todays_entry_count
  , entry_from_lw
  , entry_to_lw
  , todays_entry_count_lw
  , treatment_minutes_in_hour_lw
  , date_diff('hour', cast(entry_to as timestamp), cast(business_datetime as timestamp)) as n_hour_extend
  , date_diff('hour', cast(business_datetime as timestamp), cast(entry_from as timestamp)) as n_hour_advance
from
  available_timeslot
  left join (select property_id, business_date, business_hour, quest_time_slot_type_1 from available_quest_1) using (property_id, business_date, business_hour)
  left join (select property_id, business_date, business_hour, quest_time_slot_type_2, therapist_id from available_quest_2) using (property_id, business_date, business_hour, therapist_id)
  left join (
      select * 
      from tp_entry
      union all
      select property_id, therapist_id, business_date, null as entry_from, null as entry_to, null as todays_entry_count
      from tp_entry_last_week
        left join (select property_id, therapist_id, business_date, 1 as flag from tp_entry) using (property_id, therapist_id, business_date)
      where flag is null
    ) using (property_id, business_date)
  left join tp_entry_last_week using (property_id, business_date, therapist_id)
  left join tp_order_last_week using (property_id, business_date, therapist_id, business_hour)
  inner join (select therapist_id, therapist_no, professional_name from _integration_datamart.mst_therapist where contract_type = '03') using (therapist_id)
  left join (
      select therapist_id, email
      from _l0_mysql_core.therapist_contact
        inner join (
          select therapist_id, max(time) as time
          from _l0_mysql_core.therapist_contact
          group by therapist_id
        ) using (therapist_id, time)
    ) using (therapist_id)
where
  case
    when dow(cast(td_time_string(td_scheduled_time(), 'd!', 'jst') as date)) = 5
      then td_time_parse(business_date, 'jst') between td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '2d', 'jst') and td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '4d', 'jst')
    else td_time_parse(business_date, 'jst') = td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '2d', 'jst')
  end
  and (
    td_time_parse(business_date, 'jst') = td_date_trunc('day', td_time_parse(entry_from, 'jst'), 'jst')
    or td_time_parse(business_date, 'jst') = td_date_trunc('day', td_time_parse(entry_from_lw, 'jst'), 'jst')
  )
