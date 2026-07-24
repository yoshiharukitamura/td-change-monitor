-- drop table if exists l2_tp_suggest.suggest_rawdata;
-- create table l2_tp_suggest.suggest_rawdata as
delete from l2_tp_suggest.suggest_rawdata where time = td_date_trunc('day', td_scheduled_time(), 'jst');
insert into l2_tp_suggest.suggest_rawdata
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
    cls_sufficiency -- 現行モデルのテーブル
    left join (select property_id, shop_no, shop_name from _integration_datamart.mst_shop) using (property_id)
  where
    td_time_parse(business_date, 'jst') >= td_date_trunc('day', td_scheduled_time(), 'jst')
    and coalesce(entry_slot, 0) < (td1 + td2 + td3)
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
    cls_time_slot_detail
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
    cls_time_slot_detail
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
, available_quest as (
  select distinct
    quest_time_slot_id
    , property_id
    , substr(date, 1, 10) as business_date
    , td_time_string(td_date_trunc('week', td_time_parse(date, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , cast(substr(start_time, 1, 2) as bigint) as business_hour
    , quest_time_slot_type
  from
    quest_time_slot
  where
    time = td_date_trunc('day', td_scheduled_time(), 'jst')
    and deleted = 0
    and therapist_id is null
)
, merged_ab as (
  select
    case
        when coalesce(shop_has_quest, 0) = 1 then 'A'
        when coalesce(shop_has_quest, 0) = 0 then 'B'
      end as pattern
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
    , quest_time_slot_type
    , therapist_id
    , entry_from
    , entry_to
    , todays_entry_count
    , cast(null as varchar) as entry_from_lw
    , cast(null as varchar) as entry_to_lw
    , cast(null as bigint) as todays_entry_count_lw
    , date_diff('hour', cast(entry_to as timestamp), cast(business_datetime as timestamp)) as n_hour_extend
    , date_diff('hour', cast(business_datetime as timestamp), cast(entry_from as timestamp)) as n_hour_advance
    , cast(null as bigint) as treatment_minutes_in_hour_lw
  from
    available_timeslot
    left join tp_entry using (property_id, business_date)
    left join (select property_id, business_date, business_hour, quest_time_slot_type from available_quest) using (property_id, business_date, business_hour)
    left join (select distinct property_id, business_week, 1 as shop_has_quest from available_quest) using (property_id, business_week)
  where
    shop_no < 6000
    and not td_time_parse(business_datetime, 'jst') between td_time_parse(entry_from, 'jst') and td_time_parse(entry_to, 'jst')
)
, merged_c as (
  select
    'C' as pattern
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
    , cast(null as varchar) as quest_time_slot_type
    , therapist_id
    , entry_from
    , entry_to
    , todays_entry_count
    , entry_from_lw
    , entry_to_lw
    , todays_entry_count_lw
    , date_diff('hour', cast(entry_to as timestamp), cast(business_datetime as timestamp)) as n_hour_extend
    , date_diff('hour', cast(business_datetime as timestamp), cast(entry_from as timestamp)) as n_hour_advance
    , treatment_minutes_in_hour_lw
  from
    available_timeslot
    left join tp_entry using (property_id, business_date)
    left join tp_entry_last_week using (property_id, business_date, therapist_id)
    left join tp_order_last_week using (property_id, business_date, therapist_id, business_hour)
  where
    shop_no >= 6000
    and not td_time_parse(business_datetime, 'jst') between td_time_parse(entry_from, 'jst') and td_time_parse(entry_to, 'jst')
    and td_time_parse(business_datetime, 'jst') between td_time_parse(entry_from_lw, 'jst') and td_time_parse(entry_to_lw, 'jst')
)

select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , *
from (
    select * from merged_ab
    union all 
    select * from merged_c
  )
  left join (select therapist_id, therapist_no, professional_name from _integration_datamart.mst_therapist) using (therapist_id)
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
  and td_time_parse(business_date, 'jst') = td_date_trunc('day', td_time_parse(entry_from, 'jst'), 'jst')
;

