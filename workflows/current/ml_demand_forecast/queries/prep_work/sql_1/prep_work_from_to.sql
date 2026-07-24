with log as (
  select
    t1.property_id as mst_shop_id
    , t1.therapist_id
    , td_time_parse(t1.date, 'jst') as date_unix
    , if(length(start_time) = 4 and length(end_time) = 4, start_time, '0000') as start_time
    , if(length(start_time) = 4 and length(end_time) = 4, end_time, '0000') as end_time
    , if(length(break_start_time) = 4 and length(break_end_time) = 4, break_start_time, '0000') as break_start_time
    , if(length(break_start_time) = 4 and length(break_end_time) = 4, break_end_time, '0000') as break_end_time
  from
    _l1_mysql_core.daily_time_slot as t1
  where
    td_time_range(t1.time, null, td_scheduled_time()+1, 'jst')
    and td_time_range(td_time_parse(t1.date, 'jst'), '2020-08-01', null, 'jst')
    and length(t1.start_time) = 4
    and t1.deleted = 0
    and t1.fix_flag = 1
)
select
  date_unix as time
  , mst_shop_id
  , therapist_id
  , td_time_add(td_time_add(date_unix, start_hour||'h', 'jst'), start_minute||'m', 'jst') as start_dt
  , td_time_add(td_time_add(date_unix, end_hour||'h', 'jst'), end_minute||'m', 'jst') as end_dt
  , td_time_add(td_time_add(date_unix, break_start_hour||'h', 'jst'), break_start_minute||'m', 'jst') as break_start_dt
  , td_time_add(td_time_add(date_unix, break_end_hour||'h', 'jst'), break_end_minute||'m', 'jst') as break_end_dt
from (
    select
      *
      , cast(cast(substr(start_time, 1, 2) as bigint) as varchar) as start_hour
      , cast(cast(substr(start_time, 3, 2) as bigint) as varchar) as start_minute
      , cast(cast(substr(end_time, 1, 2) as bigint) as varchar) as end_hour
      , cast(cast(substr(end_time, 3, 2) as bigint) as varchar) as end_minute
      , cast(cast(substr(break_start_time, 1, 2) as bigint) as varchar) as break_start_hour
      , cast(cast(substr(break_start_time, 3, 2) as bigint) as varchar) as break_start_minute
      , cast(cast(substr(break_end_time, 1, 2) as bigint) as varchar) as break_end_hour
      , cast(cast(substr(break_end_time, 3, 2) as bigint) as varchar) as break_end_minute
    from
      log
  )
