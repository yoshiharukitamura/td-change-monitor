-- drop table if exists l2_tp_suggest.suggest_history;
-- create table l2_tp_suggest.suggest_history as
delete from l2_tp_suggest.suggest_history where time = td_date_trunc('day', td_scheduled_time(), 'jst');
insert into l2_tp_suggest.suggest_history
select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , 'processind_date' as time_means
  , td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as time_fmt
  , *
from (
    select
      pattern
      , email
      , therapist_no
      , professional_name
      , shop_no
      , shop_name
      , business_month
      , business_day
      , business_dow
      , entry_from
      , entry_to
      , cast(null as varchar) as entry_from_lw
      , cast(null as varchar) as entry_to_lw
      , cast(null as double) as utilization_advance
      , cast(null as double) as utilization_extend
      , if(min(advance_to) is not null, min(if(business_hour<=advance_to, business_hour))) as suggeststart1
      , if(min(advance_to) is not null, max(if(business_hour<=advance_to, business_hour)+1)) as suggestend1
      , if(min(extend_from) is not null, min(if(business_hour>=extend_from, business_hour))) as suggeststart2
      , if(min(extend_from) is not null, max(if(business_hour>=extend_from, business_hour)+1)) as suggestend2
      , case
          when pattern = 'A' then '上記はクエストが残っている枠あります。'
          when pattern = 'B' then '上記はお客様の来店が多く見込まれる時間です。'
        end as message
      , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
    from
      l2_tp_suggest.suggest_rawdata
      left join (
          select therapist_no, shop_no, business_date, max(business_hour) as advance_to
          from l2_tp_suggest.suggest_rawdata
          where
            time = td_date_trunc('day', td_scheduled_time(), 'jst')
            and n_hour_advance between 1 and 3
            and case
                  when pattern = 'A' then quest_time_slot_type is not null
                  when pattern = 'B' then not_enough_td2 = 'yes'
                end
          group by therapist_no, shop_no, business_date
        ) using (therapist_no, shop_no, business_date)
      left join (
          select therapist_no, shop_no, business_date, min(business_hour) as extend_from
          from l2_tp_suggest.suggest_rawdata
          where
            time = td_date_trunc('day', td_scheduled_time(), 'jst')
            and n_hour_extend between 1 and 3
            and case
                  when pattern = 'A' then quest_time_slot_type is not null
                  when pattern = 'B' then not_enough_td2 = 'yes'
                end
          group by therapist_no, shop_no, business_date
        ) using (therapist_no, shop_no, business_date)
    where
      time = td_date_trunc('day', td_scheduled_time(), 'jst')
      and (
          n_hour_advance between 1 and 3
          or n_hour_extend between 1 and 3
        )
      and pattern in ('A', 'B')
      and (advance_to is not null or extend_from is not null)
    group by
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

    union all

    select
      pattern
      , email
      , therapist_no
      , professional_name
      , shop_no
      , shop_name
      , business_month
      , business_day
      , business_dow
      , entry_from
      , entry_to
      , entry_from_lw
      , entry_to_lw
      , utilization_advance
      , utilization_extend
      , if(min(utilization_advance) >= 0.5, min(if(business_hour<cast(substr(entry_from, 12, 2) as bigint), business_hour))) as suggeststart1
      , if(min(utilization_advance) >= 0.5, max(if(business_hour<cast(substr(entry_from, 12, 2) as bigint), business_hour))+1) as suggestend1
      , if(min(utilization_extend) >= 0.5, min(if(business_hour>cast(substr(entry_to, 12, 2) as bigint), business_hour))) as suggeststart2
      , if(min(utilization_extend) >= 0.5, max(if(business_hour>cast(substr(entry_to, 12, 2) as bigint), business_hour))+1) as suggestend2
      , '上記は先週入店いただき、施術が発生した時間です。' as message
      , 'https://www.riraku-sys.jp/riraku-room/EntrySlot/'||cast(min(property_id) as varchar)||'/'||min(business_week) as url
    from
      l2_tp_suggest.suggest_rawdata
      left join (
          select therapist_no, shop_no, business_date
            , sum(if(business_hour < cast(substr(entry_from, 12, 2) as bigint), treatment_minutes_in_hour_lw))
                / nullif(cast(count(if(business_hour < cast(substr(entry_from, 12, 2) as bigint), 1))*60 as double), 0) as utilization_advance
            , sum(if(business_hour > cast(substr(entry_to, 12, 2) as bigint), treatment_minutes_in_hour_lw))
                / nullif(cast(count(if(business_hour > cast(substr(entry_to, 12, 2) as bigint), 1))*60 as double), 0) as utilization_extend
          from l2_tp_suggest.suggest_rawdata
          group by therapist_no, shop_no, business_date
        ) using (therapist_no, shop_no, business_date)
    where
      time = td_date_trunc('day', td_scheduled_time(), 'jst')
      and (
          n_hour_advance between 1 and 3
          or n_hour_extend between 1 and 3
        )
      and pattern in ('C')
      and (utilization_advance >= 0.5 or utilization_extend >= 0.5)
    group by
      1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
  )
;

