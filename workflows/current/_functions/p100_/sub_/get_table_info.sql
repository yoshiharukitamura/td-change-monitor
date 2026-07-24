select
  td_time_string(min(time), 's!', 'jst') as min_time
  , td_time_string(max(time), 's!', 'jst') as max_time
  , count(1) as records
from
  ${table_schema}.${table_name}
