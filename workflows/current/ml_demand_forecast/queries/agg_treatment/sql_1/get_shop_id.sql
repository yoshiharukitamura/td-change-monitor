select array_join(array_agg(cols order by id),', ') cols from
(select
  id
  , 'coalesce(if(element_at(kv,'''||cast(id as varchar)||''') is not null, kv['''||cast(id as varchar)||'''], null), 0) as s'||cast(id as varchar) as cols
from
  _l1_mysql_pos.mst_shops
group by
  id
order by
  id
  )