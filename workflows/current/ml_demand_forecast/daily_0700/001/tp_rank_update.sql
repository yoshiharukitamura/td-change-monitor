with datetime_list as (
  select distinct
    td_time_add(cast(reference_year+year_num as varchar)||'-01-01', cast(day_num as varchar)||'d', 'jst') as datetime
  from
    (select 2018 as reference_year) as t1
    cross join unnest (
        sequence(0, 99, 1)
      ) AS t2(year_num)
    cross join unnest (
        sequence(0, 365, 1)
      ) AS t3(day_num)
)
, processing_date_list as (
  select distinct
    td_date_trunc('week', datetime, 'jst') as processing_week
  from
    datetime_list
  where
    datetime < td_scheduled_time()
)

select
  t2.therapist_id
  , max(t2.therapist_no) as therapist_no
  , td_time_string(t1.processing_week, 'd!', 'jst') as processing_week
  , case max_by(t2.therapist_class_type, t2.updated_datetime)
    when '01' then 'A1'
    when '02' then 'A2'
    when '03' then 'A3'
    when '04' then 'A4'
    when '05' then 'B'
    else null end as therapist_rank_class
from
  processing_date_list as t1
  left join _l0_mysql_core.therapist as t2 on t1.processing_week >= td_time_parse(t2.updated_datetime, 'jst')
where
  deleted = 0
group by
  t2.therapist_id
  , t1.processing_week

