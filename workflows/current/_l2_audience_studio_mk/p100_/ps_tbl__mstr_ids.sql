with hp_customers as (
  select
    dtb_customer_id as customer_id
  from
    _l1_mysql_hp.customers
  where
    coalesce(deleted, 0) = 0
  group by
    1
)

, pos_customers as (
  select
    id as customer_id
  from
    _l1_mysql_pos.customers
  where
    coalesce(deleted, 0) = 0
    and coalesce(deactivated, 0) = 0
  group by
    1
)

, merged as (
  select * from hp_customers
   union all
  select * from pos_customers
)

select
  customer_id as mstr__id
  , customer_id
from
  merged
where
  customer_id > 0
group by
  1,2
order by
  1,2