select
  table_schema
  , table_name
  , ordinal_position
  , column_name
  , data_type
  , '${td.last_results.min_time}' as min_time
  , '${td.last_results.max_time}' as max_time
  , ${td.last_results.records} as records
from
  information_schema.columns
where
  table_schema = '${table_schema}'
  and table_name = '${table_name}'
order by
  table_name
  , ordinal_position