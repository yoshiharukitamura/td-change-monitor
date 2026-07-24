with work as (
  select
    time
    , mst_shop_id
    , td_time_string(td_date_trunc('hour', work_time, 'jst'), 's!', 'jst') as work_time
    , count(1) as work_count
  from
    prep_work_vtable_minutely
  where
    td_time_range(time, '2020-08-01', td_scheduled_time(), 'jst')
  group by
    1,2,3
)
, break as (
  select
    time
    , mst_shop_id
    , td_time_string(td_date_trunc('hour', break_time, 'jst'), 's!', 'jst') as break_time
    , count(1) as break_count
  from
    prep_break_vtable_minutly
  where
    td_time_range(time, '2020-08-01', td_scheduled_time(), 'jst')
  group by
    1,2,3
)
select
  t1.time
  , t1.mst_shop_id
  , t1.work_time
  , coalesce(t1.work_count, 0) - coalesce(t2.break_count, 0) as work_count
from
  work as t1
  left join break as t2 on t1.mst_shop_id = t2.mst_shop_id and t1.work_time = t2.break_time
;


