select
  td_date_trunc('week', td_date_trunc('week', ${reference_time}, 'jst'), 'jst') as time
  , td_time_string(td_date_trunc('week', td_date_trunc('week', ${reference_time}, 'jst'), 'jst'), 'd!', 'jst') as processing_date
  , substr(date, 1, 10) as business_date
  , td_time_string(td_date_trunc('week', td_time_parse(substr(date, 1, 10), 'jst'), 'jst'), 'd!', 'jst') as business_week
  , date_diff('week', cast(td_time_string(td_date_trunc('week', td_date_trunc('week', ${reference_time}, 'jst'), 'jst'), 'd!', 'jst') as date), cast(td_time_string(td_date_trunc('week', td_time_parse(substr(date, 1, 10), 'jst'), 'jst'), 'd!', 'jst') as date)) as week_diff
  , substr('月火水木金土日', dow(cast(substr(date, 1, 10) as date)), 1) as business_dow
  , therapist_id
  , property_id
  , cast(substr(start_time, 1, 2) as bigint) as business_hour
  , if(substr(end_time, 3, 2) = '30', 0.5, 1.0) as entry_slot
from
  _l0_mysql_core.time_slot_detail
  inner join (
    select time_slot_detail_id, max(time) as time
    from _l0_mysql_core.time_slot_detail
    where time <= td_date_trunc('week', td_date_trunc('week', ${reference_time}, 'jst'), 'jst')
    group by time_slot_detail_id
  ) using (time_slot_detail_id, time)
where
  time <= td_date_trunc('week', ${reference_time}, 'jst')
  and td_time_parse(date, 'jst') between td_time_add(td_date_trunc('week', ${reference_time}, 'jst'), '-7day') and td_time_add(td_date_trunc('week', ${reference_time}, 'jst'), '41day')
  and coalesce(deleted, 0) = 0
  and therapist_id is not null
