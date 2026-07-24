select
  table_schema
  , table_name
  , row_number() over (order by table_schema, table_name) as seq
from
  information_schema.tables
where
  regexp_like(table_schema, '^(${database_list[data_catalog].join("|")})$')
order by
  table_schema
  , table_name