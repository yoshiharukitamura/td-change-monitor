with akaden as (
  select
    id
  from
    _l1_mysql_pos.orders
  where
    td_time_range(time, null, td_time_add(td_scheduled_time(), '1d', 'jst'), 'jst')
    and coalesce(deleted, 0) = 0
    and status <> 2
  group by
    id
)

select
  td_date_trunc('day', td_time_add(td_time_parse(t1.treatment_start_datetime, 'jst'), '-6h', 'jst'), 'jst') as time
  , t1.id
  , t1.mst_shop_id
  , td_time_parse(t1.treatment_start_datetime, 'jst') as raw_treatment_start_time
  , td_time_parse(t1.treatment_start_datetime, 'jst') + (t1.total_amount_of_treatment_minutes * 60) as raw_treatment_end_time
from
  _l1_mysql_pos.orders as t1
  left join akaden on t1.original_order_id = akaden.id
where
  td_time_range(t1.time, null, td_time_add(td_scheduled_time(), '1d', 'jst'), 'jst')
  and coalesce(t1.deleted, 0) = 0
  and t1.order_type = 1
  and akaden.id is null
  and t1.total_amount_of_treatment_minutes > 0
  and t1.status = 2
group  by
  1,2,3,4,5