-- drop table if exists l2_tp_suggest.suggest_history_v2_tmp;
-- create table l2_tp_suggest.suggest_history_v2_tmp as
delete from l2_tp_suggest.suggest_history_v2_tmp where time = td_date_trunc('day', td_scheduled_time(), 'jst') and priority between 1 and 5;

insert into l2_tp_suggest.suggest_history_v2_tmp
/* A: 前後3時間にクエストが残っていて、且つその枠に先週入店していて稼働率50％以上の時間がある */
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , 'A' as pattern
  , 1 as priority
  , min(if(
        n_hour_advance between 1 and 3
        and quest_time_slot_type is not null
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggeststart1
  , max(if(
        n_hour_advance between 1 and 3
        and quest_time_slot_type is not null
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggestend1
  , min(if(
        n_hour_extend between 1 and 3
        and quest_time_slot_type is not null
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggeststart2
  , max(if(
        n_hour_extend between 1 and 3
        and quest_time_slot_type is not null
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggestend2
  , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
from
  l2_tp_suggest.suggest_rawdata_v2
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and (n_hour_advance between 1 and 3 or n_hour_extend between 1 and 3)
  and quest_time_slot_type is not null
  and treatment_minutes_in_hour_lw >= 60*0.5
group by
  email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
;

/* B: 前後3時間にTD123が残っていて、且つその枠に先週入店していて稼働率50％以上の時間がある */
insert into l2_tp_suggest.suggest_history_v2_tmp
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , 'B' as pattern
  , 2 as priority
  , min(if(
        n_hour_advance between 1 and 3
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggeststart1
  , max(if(
        n_hour_advance between 1 and 3
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggestend1
  , min(if(
        n_hour_extend between 1 and 3
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggeststart2
  , max(if(
        n_hour_extend between 1 and 3
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggestend2
  , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
from
  l2_tp_suggest.suggest_rawdata_v2
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and (n_hour_advance between 1 and 3 or n_hour_extend between 1 and 3)
  and treatment_minutes_in_hour_lw >= 60*0.5
group by
  email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
;

/* C: 前後3時間にクエストが残っている */
insert into l2_tp_suggest.suggest_history_v2_tmp
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , 'C' as pattern
  , 3 as priority
  , min(if(
        n_hour_advance between 1 and 3
        and quest_time_slot_type is not null
      , business_hour)) as suggeststart1
  , max(if(
        n_hour_advance between 1 and 3
        and quest_time_slot_type is not null
        , business_hour)) as suggestend1
  , min(if(
        n_hour_extend between 1 and 3
        and quest_time_slot_type is not null
        , business_hour)) as suggeststart2
  , max(if(
        n_hour_extend between 1 and 3
        and quest_time_slot_type is not null
      , business_hour)) as suggestend2
  , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
from
  l2_tp_suggest.suggest_rawdata_v2
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and (n_hour_advance between 1 and 3 or n_hour_extend between 1 and 3)
  and quest_time_slot_type is not null
group by
  email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
;

/* D: 前後3時間にTD123が残っていて、且つその枠に先週入店していて稼働率50％以上の時間がある */
insert into l2_tp_suggest.suggest_history_v2_tmp
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , 'D' as pattern
  , 4 as priority
  , min(if(
        n_hour_advance between 1 and 3
      , business_hour)) as suggeststart1
  , max(if(
        n_hour_advance between 1 and 3
        , business_hour)) as suggestend1
  , min(if(
        n_hour_extend between 1 and 3
        , business_hour)) as suggeststart2
  , max(if(
        n_hour_extend between 1 and 3
      , business_hour)) as suggestend2
  , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
from
  l2_tp_suggest.suggest_rawdata_v2
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and (n_hour_advance between 1 and 3 or n_hour_extend between 1 and 3)
group by
  email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
;




delete from l2_tp_suggest.suggest_history_v2_tmp where time = td_date_trunc('day', td_scheduled_time(), 'jst') and priority between 6 and 10;

insert into l2_tp_suggest.suggest_history_v2_tmp
/* F: 前週入店した枠にクエストが残っていて、且つその枠に稼働率50％以上の時間がある */
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , 'F' as pattern
  , 6 as priority
  , min(if(
        business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
        and quest_time_slot_type is not null
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggeststart1
  , max(if(
        business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
        and quest_time_slot_type is not null
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggestend1
  , null as suggeststart2
  , null as suggestend2
  , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
from
  l2_tp_suggest.suggest_rawdata_v2
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and todays_entry_count is null
  and business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
  and quest_time_slot_type is not null
  and treatment_minutes_in_hour_lw >= 60*0.5
group by
  email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
;

/* G: 前週入店した枠にTD123が残っていて、且つその枠に先週入店していて稼働率50％以上の時間がある */
insert into l2_tp_suggest.suggest_history_v2_tmp
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , 'G' as pattern
  , 7 as priority
  , min(if(
        business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggeststart1
  , max(if(
        business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
        and treatment_minutes_in_hour_lw >= 60*0.5
      , business_hour)) as suggestend1
  , null as suggeststart2
  , null as suggestend2
  , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
from
  l2_tp_suggest.suggest_rawdata_v2
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and todays_entry_count is null
  and business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
  and treatment_minutes_in_hour_lw >= 60*0.5
group by
  email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
;

/* H: 前週入店した枠にクエストが残っている */
insert into l2_tp_suggest.suggest_history_v2_tmp
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , 'H' as pattern
  , 8 as priority
  , min(if(
        business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
        and quest_time_slot_type is not null
      , business_hour)) as suggeststart1
  , max(if(
        business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
        and quest_time_slot_type is not null
      , business_hour)) as suggestend1
  , null as suggeststart2
  , null as suggestend2
  , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
from
  l2_tp_suggest.suggest_rawdata_v2
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and todays_entry_count is null
  and business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
  and quest_time_slot_type is not null
group by
  email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
;

/* I: 前週入店した枠にTD123が残っていてる */
insert into l2_tp_suggest.suggest_history_v2_tmp
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , 'I' as pattern
  , 9 as priority
  , min(if(
        business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
      , business_hour)) as suggeststart1
  , max(if(
        business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
      , business_hour)) as suggestend1
  , null as suggeststart2
  , null as suggestend2
  , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
from
  l2_tp_suggest.suggest_rawdata_v2
where
  time = td_date_trunc('day', td_scheduled_time(), 'jst')
  and todays_entry_count is null
  and business_hour between cast(substr(entry_from_lw, 12, 2) as bigint) and cast(substr(entry_to_lw, 12, 2) as bigint)
group by
  email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
;


-- drop table if exists l2_tp_suggest.suggest_history;
-- create table l2_tp_suggest.suggest_history as
delete from l2_tp_suggest.suggest_history_v2 where time = td_date_trunc('day', td_scheduled_time(), 'jst');
insert into l2_tp_suggest.suggest_history_v2
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , pattern
  , email, therapist_no, professional_name, shop_no, shop_name, business_month, business_day, business_dow, entry_from, entry_to, entry_from_lw, entry_to_lw
  , suggeststart1
  , suggestend1
  , suggeststart2
  , suggestend2
  , case pattern
      when 'A' then '上記は先週入店いただき、施術が発生した時間で、今週クエストが残っている枠があります。'
      when 'B' then '上記は先週入店いただき、施術が発生した時間で、今週もお客様の来店が多く見込まれる時間です。'
      when 'C' then '上記はクエストが残っている枠あります。'
      when 'D' then '上記はお客様の来店が多く見込まれる時間です。'
      when 'F' then '上記は先週入店いただき、施術が発生した時間で、今週クエストが残っている枠があります。'
      when 'G' then '上記は先週入店いただき、施術が発生した時間で、今週もお客様の来店が多く見込まれる時間です。'
      when 'H' then '上記は先週入店いただき、クエストが残っている枠あります。'
      when 'I' then '上記は先週入店いただき、お客様の来店が多く見込まれる時間です。'
    end as message
  , url
from (
    select
      *
      , row_number() over (partition by business_month, business_day, therapist_no order by priority, shop_no) as seq
    from
      suggest_history_v2_tmp
    where
      time = td_date_trunc('day', td_scheduled_time(), 'jst')
  )
where
  seq = 1
order by
  priority

