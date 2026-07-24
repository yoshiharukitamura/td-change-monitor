select
  time
  , td_time_string(treatment_time, 's!', 'jst') as treatment_time
  , ${td.last_results.cols}
from (
  select
    time
    , treatment_time
    , map_agg(cast(mst_shop_id as varchar), treatment_count) as kv
  from
    l1_datamart.prep_treatment_vtable_hourly_fixed_2
  where
    td_time_range(time, '2018-01-01', td_scheduled_time(), 'jst')
  group by
    time
    , treatment_time
)
order by
  1,2
