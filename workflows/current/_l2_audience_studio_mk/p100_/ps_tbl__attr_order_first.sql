with first_app as (
  select
    dtb_customer_id as customer_id
    , min(td_time_parse(created_app, 'jst')) as first_app_registered_date_datetime
  from
    _l1_mysql_hp.customers
  where
    coalesce(deleted, 0) = 0
  group by
    1 
)

, first_order as (
  select
    customer_id
    , min(td_time_parse(registered_business_date, 'jst')) as first_order_date_datetime
  from
    _l1_mysql_pos.orders
  where
    coalesce(deleted, 0) = 0
  group by
    1
)

, merged as (
select
  coalesce(t0.customer_id, t1.customer_id) as mstr__id
  , first_app_registered_date_datetime
  , first_order_date_datetime
from
  first_app as t0
full outer join
  first_order as t1
  on t0.customer_id = t1.customer_id
)

select
  mstr__id
  , first_app_registered_date_datetime
  , first_order_date_datetime
from
  merged
where
  mstr__id is not null