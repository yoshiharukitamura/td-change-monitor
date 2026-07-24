drop table if exists l2_shop_db_dev.time_slot_progress_ss_list;
create table l2_shop_db_dev.time_slot_progress_ss_list as
with datetime_list as (
  select
    business_week
    , td_time_add(business_week, cast(offset_week*7 as varchar)||'d', 'jst') as processing_datetime
    , date
  from (
      select distinct
        td_date_trunc('week', td_time_parse(date, 'jst'), 'jst') as business_week
        , date
      from
        _l0_mysql_core.time_slot_detail
      where
        td_time_range(td_time_parse(date, 'jst'), '2022-04-01', null, 'jst')
    ) cross join unnest(
      sequence(-5, 1, 1)
    ) as t(offset_week)
  -- where
  --   offset_week <> 0
)

select
  if(processing_datetime > td_time_parse(max_by(date, time), 'jst'), td_time_add(processing_datetime, '1d', 'jst'), processing_datetime) as processing_datetime
  , if(processing_datetime > td_time_parse(max_by(date, time), 'jst'), '05_confirmed', '01_week_offset') as flag
  , time_slot_detail_id
  , max(time) as time
  , max_by(deleted, time) as deleted
  , max_by(entry_status, time) as entry_status
from
  _l0_mysql_core.time_slot_detail
  inner join datetime_list using (date)
where
  time <= td_time_add(processing_datetime, '1d', 'jst')
group by
  time_slot_detail_id
  , processing_datetime
;



delete from l2_shop_db_dev.time_slot_progress_rawdata where flag = '03_date_offset'
;

insert into l2_shop_db_dev.time_slot_progress_ss_list
with datetime_list as (
  select
    business_week
    , td_time_add(business_date, cast(offset_date as varchar)||'d', 'jst') as processing_datetime
    , date
  from (
      select distinct
        td_date_trunc('week', td_time_parse(date, 'jst'), 'jst') as business_week
        , td_time_parse(date, 'jst') as business_date
        , date
      from
        _l0_mysql_core.time_slot_detail
      where
        td_time_range(td_time_parse(date, 'jst'), '2022-04-01', null, 'jst')
  ) cross join unnest(
      sequence(-3, 0, 1)
    ) as t(offset_date)
)

select
  processing_datetime
  , '03_date_offset' as flag
  , time_slot_detail_id
  , max(time) as time
  , max_by(deleted, time) as deleted
  , max_by(entry_status, time) as entry_status
from
  _l0_mysql_core.time_slot_detail
  inner join datetime_list using (date)
where
  time <= processing_datetime
group by
  time_slot_detail_id
  , processing_datetime
;



delete from l2_shop_db_dev.time_slot_progress_rawdata where flag = '04_hour_offset'
;

insert into l2_shop_db_dev.time_slot_progress_ss_list
with datetime_list as (
  select
    business_week
    , td_time_add(business_datetime, cast(offset_hour as varchar)||'h', 'jst') as processing_datetime
    , date
    , start_time
  from (
      select distinct
        td_date_trunc('week', td_time_parse(date, 'jst'), 'jst') as business_week
        , td_time_add(td_time_parse(date, 'jst'), substr(start_time, 1, 2)||'h', 'jst') as business_datetime
        , date
        , start_time
      from
        _l0_mysql_core.time_slot_detail
      where
        td_time_range(td_time_parse(date, 'jst'), '2022-04-01', null, 'jst')
  ) cross join unnest(
      sequence(-3, 0, 1)
    ) as t(offset_hour)
)

select
  processing_datetime
  , '04_hour_offset' as flag
  , time_slot_detail_id
  , max(time) as time
  , max_by(deleted, time) as deleted
  , max_by(entry_status, time) as entry_status
from
  _l0_mysql_core.time_slot_detail
  inner join datetime_list using (date, start_time)
where
  time <= td_time_add(processing_datetime, '1d', 'jst')
group by
  time_slot_detail_id
  , processing_datetime

