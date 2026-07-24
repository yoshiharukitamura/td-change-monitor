drop table if exists l2_shop_db_dev.time_slot_progress_rawdata;
create table l2_shop_db_dev.time_slot_progress_rawdata as
select
  flag
  , td_time_string(processing_datetime, 's!', 'jst') as processing_datetime
  , time_slot_detail_id
  , time
  , property_id as shop_id
  , therapist_id
  , td_time_string(td_date_trunc('week', td_time_parse(date, 'jst'), 'jst'), 'd!', 'jst') as business_week
  , substr(date, 1, 10) as business_date
  , td_time_string(td_time_add(td_time_parse(date, 'jst'), substr(start_time, 1, 2)||'h', 'jst'), 's!', 'jst') as business_datetime
  , cast(substr(start_time, 1, 2) as bigint) as business_hour
  , if(cast(end_time as bigint)-cast(start_time as bigint)=100, 1.0, 0.5) as time_slot
from
  _l0_mysql_core.time_slot_detail
  inner join l2_shop_db_dev.time_slot_progress_ss_list using (time_slot_detail_id, time, entry_status, deleted)
where
  entry_status = '04'
  and deleted = 0
  -- and td_time_parse(entry_datetime, 'jst') < processing_datetime
  -- and (
  --     (regexp_like(flag, '03_date_offset|04_hour_offset') and td_time_parse(entry_datetime, 'jst') < processing_datetime)
  --     or
  --     (regexp_like(flag, '01_week_offset|05_confirmed'))
  --   )
  and (
      (regexp_like(flag, '01_week_offset|03_date_offset|04_hour_offset') and td_time_parse(entry_datetime, 'jst') < processing_datetime)
      or
      (regexp_like(flag, '05_confirmed'))
    )
;



delete from l2_shop_db_dev.time_slot_progress_rawdata where flag = '02_quest'
;

insert into l2_shop_db_dev.time_slot_progress_rawdata
select
  '02_quest' as flag
  , td_time_string(time, 's!', 'jst') as processing_datetime
  , time_slot_detail_id
  , time
  , property_id as shop_id
  , therapist_id
  , td_time_string(td_date_trunc('week', td_time_parse(date, 'jst'), 'jst'), 'd!', 'jst') as business_week
  , substr(date, 1, 10) as business_date
  , td_time_string(td_time_add(td_time_parse(date, 'jst'), substr(start_time, 1, 2)||'h', 'jst'), 's!', 'jst') as business_datetime
  , cast(substr(start_time, 1, 2) as bigint) as business_hour
  , if(cast(end_time as bigint)-cast(start_time as bigint)=100, 1.0, 0.5) as time_slot
from
  l0_core.time_slot_detail_fri_ss
where
  td_time_range(time, '2023-05-01', null, 'jst')
  and td_time_range(td_time_parse(date, 'jst'), '2023-05-01', null, 'jst')
  and entry_status = '04'
  and deleted = 0

