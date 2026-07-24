select
  td_time_parse(business_week, 'jst') as time
  , business_week
  , flag
  , case flag
      when '01_week_offset' then td_time_string(td_date_trunc('week', td_time_parse(processing_datetime, 'jst'), 'jst'), 'd!', 'jst')
      when '02_quest' then td_time_string(td_date_trunc('week', td_time_parse(processing_datetime, 'jst'), 'jst'), 'd!', 'jst')
      when '03_date_offset' then td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst')
      when '04_hour_offset' then td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst')
      when '05_confirmed' then td_time_string(td_date_trunc('week', td_time_parse(processing_datetime, 'jst'), 'jst'), 'd!', 'jst')
    end as processing_week      
  , case flag
      when '01_week_offset' then date_diff('week', cast(processing_datetime as timestamp), cast(business_week as timestamp))
      when '02_quest' then date_diff('week', cast(processing_datetime as timestamp), cast(business_week as timestamp))
      when '03_date_offset' then date_diff('day', cast(processing_datetime as timestamp), cast(business_date as timestamp))
      when '04_hour_offset' then date_diff('hour', cast(processing_datetime as timestamp), cast(business_datetime as timestamp))
      when '05_confirmed' then date_diff('week', cast(processing_datetime as timestamp), cast(business_week as timestamp))
    end as offset_diff
  , time_slot_detail_id
  , shop_id
  , therapist_id
  , business_datetime
  , business_date
  , business_hour
  , time_slot
from
  l2_shop_db_dev.time_slot_progress_rawdata
where
  business_hour between 9 and 23
  and (
    regexp_like(flag, '02_quest')
    or (regexp_like(flag, '01_week_offset|05_confirmed') and td_date_trunc('week', td_time_parse(processing_datetime, 'jst'), 'jst') <= td_date_trunc('week', td_scheduled_time(), 'jst'))
    or (regexp_like(flag, '03_date_offset|04_hour_offset') and td_time_parse(business_week, 'jst') < td_date_trunc('week', td_scheduled_time(), 'jst'))
  )
