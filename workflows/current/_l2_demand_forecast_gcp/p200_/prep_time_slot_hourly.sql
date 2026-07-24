with tmp_time_slot as(
  select
    time
    ,therapist_daily_report_id
    ,start_time
    ,end_time
    ,if(cast(td_time_format(ts, 'HH', 'jst') as bigint) <= 6, cast(td_time_format(ts, 'HH', 'jst') as bigint)+24, cast(td_time_format(ts, 'HH', 'jst') as bigint)) as business_hour
    ,count(ts) * 30 as time_slot
  from (
      select distinct
        td_time_parse(tdr.business_date, 'jst') as time
        ,therapist_daily_report_id
        ,case
            when cast(substr(start_time, 15, 2) as bigint) between 0 and 14 then substr(start_time, 1, 14)||'00'||substr(start_time, 17, 3)
            when cast(substr(start_time, 15, 2) as bigint) between 15 and 44 then substr(start_time, 1, 14)||'30'||substr(start_time, 17, 3)
            when cast(substr(start_time, 15, 2) as bigint) between 45 and 59 then substr(start_time, 1, 14)||'00'||substr(start_time, 17, 3)
          end as start_time
        ,case
            when cast(substr(end_time, 15, 2) as bigint) between 0 and 14 then substr(end_time, 1, 14)||'00'||substr(end_time, 17, 3)
            when cast(substr(end_time, 15, 2) as bigint) between 15 and 44 then substr(end_time, 1, 14)||'30'||substr(end_time, 17, 3)
            when cast(substr(end_time, 15, 2) as bigint) between 45 and 59 then substr(end_time, 1, 14)||'00'||substr(end_time, 17, 3)
          end as end_time
      from
        _l1_mysql_core.therapist_daily_report as tdr
      where
          coalesce(tdr.deleted, 0) = 0
          and coalesce(td_time_parse(tdr.start_time, 'jst'), 0) < coalesce(td_time_parse(tdr.end_time, 'jst'), 0)
          -- and td_time_range(td_time_parse(business_date, 'jst'), td_time_add(td_scheduled_time(), '-14d', 'jst'), td_scheduled_time(), 'jst')
    ) cross join unnest (
        sequence(td_time_parse(start_time, 'jst'), td_time_parse(end_time, 'jst'), 60*30)
      ) as t(ts)
  where
    ts < td_time_parse(end_time, 'jst')
    and date_diff('hour', cast(start_time as timestamp), cast(end_time as timestamp)) <= 24
  group by
    time
    ,therapist_daily_report_id
    ,start_time
    ,end_time
    ,td_time_format(ts, 'HH', 'jst')
)

select
  time
  , therapist_daily_report_id
  , start_time
  , end_time
  , therapist_id
  , therapist_no
  , property_id
  , shop_no
  , td_time_string(time, 'd!', 'jst') as business_date
  , td_time_string(td_time_add(time, cast(business_hour as varchar)||'h', 'jst'), 's!', 'jst') as business_datetime
  , substr('月火水木金土日', day_of_week(cast(td_time_string(time, 'd!', 'jst') as date)), 1) as business_dow
  , business_hour
  , business_hour/3*3 as start_hour_range
  , time_slot
from
  tmp_time_slot
  left join (
      select
        therapist_daily_report_id
        , therapist_id
        , therapist_no
        , property_id
        , shop_no
      from
        _l1_mysql_core.therapist_daily_report
    ) using (therapist_daily_report_id)
