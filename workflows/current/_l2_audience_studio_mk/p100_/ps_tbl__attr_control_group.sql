with customers as (
  select
    customer_id
  from (
    select dtb_customer_id as customer_id from _l1_mysql_hp.customers where coalesce(deleted, 0) = 0 group by 1
     union all
    select id as customer_id from _l1_mysql_pos.customers where coalesce(deleted, 0) = 0 and coalesce(deactivated, 0) = 0 group by 1
  )
  group by
    1
)

select
  customer_id as mstr__id
  , cast((from_base(substr(to_hex(sha256(to_utf8(cast(customer_id as varchar)))), 1, 8), 16) % 10) as varchar) as customer_id_last_digit
from
  customers