with mst_therapist as (
  select
    t0.therapist_id
    , t0.therapist_no
    , t0.professional_name
  from
    _l1_mysql_core.therapist as t0
    left join 
      _l1_mysql_core.therapist_skill as t1 on t0.therapist_id = t1.therapist_id
  where
    t0.therapist_no is not null
    and cast(t0.therapist_no as int) < 970000
    and coalesce(t1.s_rank_flag, 0) = 0
)

, mst_time_slot as (
  select
    distinct
    business_date
    , business_dow
    , holiday_type
    , holiday_name
    , business_hour
    , business_week
    , business_datetime as time_slot
  from
    _integration_datamart.mst_datetime
  where
    substr(business_date, 1, 4) >= '2024'
)
/* マスタ類 ここまで*/

/* 施設利用時間 ここから */
, prep_facilities_time as (
  select
    t0.therapist_id
    , t1.therapist_no
    , t0.shop_no
    , t0.property_id
    , business_date
    , date_parse(substr(start_time, 1, 19), '%Y-%m-%d %H:%i:%s') AS start_ts
    , date_parse(substr(end_time, 1, 19), '%Y-%m-%d %H:%i:%s')   AS end_ts
    , facilities_usage_time
    , break_time
  from
    _l1_mysql_core.therapist_daily_report as t0
    inner join
      mst_therapist as t1
      on t0.therapist_id = t1.therapist_id
         and coalesce(t0.deleted, 0) = 0
    inner join
      _l1_mysql_core.property t2
      on t0.property_id = t2.property_id
         and t2.shop_brand is not null
         and t2.shop_brand not in ('05','06')
  where
    td_time_parse(end_time, 'jst') - td_time_parse(start_time, 'jst') > break_time * 60
    and substr(business_date, 1, 10) >= '2024-01-01'
)

, prep_facilities_ts as (
  select
    therapist_no
    , shop_no
    , business_date
    , start_ts
    , end_ts
    , facilities_usage_time
    , break_time
    , time_slot
    , time_slot + interval '1' hour as slot_end
  from
    prep_facilities_time
    cross join unnest(
      sequence(date_trunc('hour', start_ts), end_ts - interval '1' second, interval '1' hour)
    ) as t(time_slot)
)

, facilities_ts as (
  select
    therapist_no
    , shop_no
    , substr(cast(time_slot as varchar), 1, 19) as time_slot
    , break_time
    , facilities_usage_time
    , break_time / ((break_time + facilities_usage_time) / 60.0) as apportion_break_minuites
    , (greatest(0, date_diff('second', greatest(start_ts, time_slot), least(end_ts, slot_end))) / 60.0)
        -  (break_time / ((break_time + facilities_usage_time) / 60.0)) as facilities_usage_minuites
  from
    prep_facilities_ts
)
/* 施設利用時間 ここまで */

/* DWB時間 ここから */
, prep_dwb_time as (
  select
    t0.working_date as business_date
    , t1.shop_no
    , t3.therapist_no
    , t3.professional_name
    , t0.mst_timetable_id
    , t0.start_time
    , t0.end_time
    , date_parse(substr(t0.start_time, 1, 19), '%Y-%m-%d %H:%i:%s') AS start_ts
    , date_parse(substr(t0.end_time, 1, 19), '%Y-%m-%d %H:%i:%s')   AS end_ts
    , t0.created
    , t0.modified
    , t0.deleted
    , t0.deleted_date
  from
    _l1_mysql_reservation.resource_timetables as t0
    inner join 
      _l1_mysql_core.property as t1
      on t0.mst_shop_id = t1.property_id
         and t0.working_date >= '2024-01-01'
         and t0.mst_timetable_id in (1, 3)
         and t0.status = 1 --TP時間枠において、最新の生きている枠のみ
         and t0.deleted <> 1 --削除されたものは除外
         and t1.shop_brand not in ('05', '06')
    inner join 
      _l1_mysql_reservation.mst_reservation_resources as t2 
      on t0.mst_reservation_resource_id = t2.id
         and t2.mst_reservation_therapist_id >= 100
         and t2.deleted <> 1
    inner join 
      mst_therapist as t3 
      on t2.mst_reservation_therapist_id = t3.therapist_id
    inner join
      (select distinct therapist_no, shop_no, business_date from prep_facilities_time) as t4
      on t3.therapist_no = t4.therapist_no
         and t0.working_date = t4.business_date
         and t1.shop_no = t4.shop_no
  where
    t0.start_time <> t0.end_time
)

, prep_dwb_ts as (
  select
    therapist_no
    , business_date
    , shop_no
    , professional_name
    , mst_timetable_id
    , start_ts
    , end_ts
    , time_slot
    , time_slot + interval '1' hour as slot_end
  from
    prep_dwb_time
    cross join unnest(
      sequence(date_trunc('hour', start_ts), date_trunc('hour', end_ts - interval '1' second), interval '1' hour)
    ) as t(time_slot)
)

, prep_dwb_ts_hour as (
  select
    business_date
    , shop_no
    , therapist_no
    , mst_timetable_id
    , time_slot
    , greatest(0, date_diff('second', greatest(start_ts, time_slot), least(end_ts, slot_end))) / 60.0 as dwb_minuites
  from
    prep_dwb_ts
)

, dwb_ts as (
  select
    therapist_no
    , shop_no
    , substr(cast(time_slot as varchar), 1, 19) as time_slot
    , sum(case when mst_timetable_id = 1 then dwb_minuites else 0 end) as dwb_entry_minuites
    , sum(case when mst_timetable_id = 3 then dwb_minuites else 0 end) as dwb_blocked_minuites
  from
    prep_dwb_ts_hour
  group by
    1,2,3
)
/* DWB時間 ここまで */

/* 最終e時間 ここから */
, final_entry_ts as (
  select
    t2.therapist_no
    , t1.shop_no
    , date_format(
        date_parse(substr(t0."date", 1, 10) || ' 00:00:00', '%Y-%m-%d %H:%i:%s')
        + (cast(floor(cast(substr(t0.start_time, 1, 2) as integer) / 24.0) as integer) * interval '1' day)
        + ((cast(substr(t0.start_time, 1, 2) as integer) % 24) * interval '1' hour),
        '%Y-%m-%d %H:%i:%s'
      ) as time_slot
    , case 
        when substr(t0.end_time, 3, 2)= '30' then 30.0
        else 60.0
      end as final_entry_minuites
  from
    _l1_mysql_core.time_slot_detail as t0
    inner join 
      _l1_mysql_core.property as t1 
      on t0.property_id = t1.property_id
         and t1.shop_brand is not null
         and t1.shop_brand not in ('05','06')
         and cast(t0.start_time as int) < cast(t0.end_time as int)
         and coalesce(t0.deleted, 0) <> 1
         and t0.date >= '2024-01-01'--2023年度までは、start_time と end_timeが1時間ピッチではなかったので除外（利用する場合は、補正対応が必要）
    inner join 
      prep_facilities_time as t2
      on t0.therapist_id = t2.therapist_id
        and t0.property_id = t2.property_id
        and t0."date" = t2.business_date
        and t2.facilities_usage_time > 0
)
/* 最終e時間 ここまで */

/* 施術時間 ここから */
, order_ts as (
  select
    therapist_no
    , shop_no
    , date_format(
        date_parse(business_date || ' 00:00:00', '%Y-%m-%d %H:%i:%s')
        + (cast(floor(business_hour / 24.0) as integer) * interval '1' day)
        + ((business_hour % 24) * interval '1' hour),
        '%Y-%m-%d %H:%i:%s'
      ) as time_slot
    , array_sort(array_distinct(array_agg(order_id)))    as order_id_list
    , array_sort(array_distinct(array_agg(customer_id))) as customer_id_list
    , sum(treatment_minutes_in_hour) as treatment_minuites
  from
    _integration_datamart.cls_order_detail
    inner join
      mst_therapist using(therapist_id)
    inner join
      _integration_datamart.mst_shop using(property_id)
  where
    business_date >= '2024-01-01'
  group by
    1,2,3
)
/* 施術時間 ここまで */

, map_tp_shop_ts as (
  select
    distinct
    therapist_no
    , shop_no
    , time_slot
  from (
    select therapist_no, shop_no, time_slot from facilities_ts
      union all
    select therapist_no, shop_no, time_slot from dwb_ts
      union all
    select therapist_no, shop_no, time_slot from final_entry_ts
  )
)

select
  td_date_trunc('day', td_time_parse(business_date, 'jst'), 'jst') as time
  , therapist_no
  , therapist_id
  , professional_name
  , shop_no
  , property_id
  , s_property_id
  , business_date
  , business_dow
  , holiday_type
  , holiday_name
  , business_hour
  , time_slot
  , coalesce(facilities_usage_minuites, 0.0) as facilities_usage_minuites
  , coalesce(apportion_break_minuites, 0.0) as apportion_break_minuites
  , coalesce(dwb_entry_minuites, 0.0) as dwb_entry_minuites
  , coalesce(dwb_blocked_minuites, 0.0) as dwb_blocked_minuites
  , coalesce(final_entry_minuites, 0.0) as final_entry_minuites
  , case 
      when coalesce(treatment_minuites, 0.0) > 60.0 then 60.0
      else coalesce(treatment_minuites, 0.0)
    end as treatment_minuites
  , order_id_list
  , customer_id_list
from
  map_tp_shop_ts
  left join mst_time_slot using (time_slot)
  left join mst_therapist using (therapist_no)
  left join mst_shop using (shop_no)
  left join facilities_ts using (therapist_no, shop_no, time_slot)
  left join dwb_ts using (therapist_no, shop_no, time_slot)
  left join final_entry_ts using (therapist_no, shop_no, time_slot)
  left join order_ts using (therapist_no, shop_no, time_slot)