with datehour_list as (
  select distinct
    td_time_add(
        td_time_add(cast(reference_year + year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst')
        , cast(hour_num as varchar)||'h'
        , 'jst'
      ) as datehour
  from
    (select 2000 as reference_year) as t0
    cross join unnest (sequence(0, 99, 1)) as t1(year_num)
    cross join unnest (sequence(0, 365, 1)) as t2(day_num)
    cross join unnest (sequence(0, 23, 1)) as t3(hour_num)
)
, prep_datehour as (
  select
    td_date_trunc('day', td_time_add(datehour, '-6h'), 'jst') as time
    , td_time_string(datehour, 's!', 'jst') as business_datetime
    , td_time_string(td_date_trunc('day', td_time_add(datehour, '-6h'), 'jst'), 'd!', 'jst') as business_date
    , td_time_string(td_date_trunc('week', td_time_add(datehour, '-6h'), 'jst'), 'd!', 'jst') as business_week
    , dow(cast(td_time_string(td_date_trunc('day', td_time_add(datehour, '-6h'), 'jst'), 'd!', 'jst') as date)) as dow_num
    , substr('月火水木金土日', dow(cast(td_time_string(td_date_trunc('day', td_time_add(datehour, '-6h'), 'jst'), 'd!', 'jst') as date)), 1) as business_dow
    , cast(td_time_format(td_time_add(datehour, '-6h'), 'HH', 'jst') as bigint) + 6 as business_hour
  from
    datehour_list
)
, holiday_list as (
  select
    substr(holiday_date, 1, 10) as business_date
    , holiday_type
    , case
        when holiday_type = '01' then '日本の祝日'
        when holiday_type = '02' then 'りらくの祝日'
        else '-'
      end as holiday_type_name
    , holiday_name
  from
    _l1_mysql_core.holiday
)

select distinct
  time
  , td_time_string(time, 's!', 'jst') as time_fmt
  , 'business_date' as time_means
  , business_date
  , holiday_type
  , holiday_type_name
  , holiday_name
  , business_week
  , business_dow
  , dow_num
  , business_hour
  , business_datetime
from
  prep_datehour
  left join holiday_list using (business_date)
order by
  business_datetime
