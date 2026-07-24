select
  time
  , mst_shop_id
  , td_date_trunc('hour', treatment_time, 'jst') as treatment_time
  , count(1) as treatment_count
from
  prep_treatment_vtable_minutely
group by
  1,2,3