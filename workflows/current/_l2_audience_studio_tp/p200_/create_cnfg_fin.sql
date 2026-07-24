select
  parent_segment_name
  , description
  , table_schema as database_name
  , case
      when regexp_like(table_name, '^ps_tbl__mstr_') then 'Master Table'
      when regexp_like(table_name, '^ps_tbl__attr_') then 'Attribute Table'
      when regexp_like(table_name, '^ps_tbl__bhvr_') then 'Behavior Table'
    end as table_type_name
  , table_name
  , case
      when regexp_like(table_name, '^ps_tbl__bhvr_') then table_name_jp
      else '-'
    end as table_name_jp
  , column_name
  , case
      when regexp_like(column_name, '_(date|datetime)$') and data_type = 'bigint' then 'timestamp'
      when data_type = 'varchar' then 'string'
      when data_type = 'bigint' then 'number'
      when data_type = 'double' then 'number'
      when data_type = 'array(varchar)' then 'string_array'
      when data_type = 'array(bigint)' then 'number_array'
      else data_type
    end as data_type
  , case
      when regexp_like(table_name, '^ps_tbl__attr_') then column_name_jp
      when regexp_like(table_name, '^ps_tbl__bhvr_') then column_name_jp
      else '-'
    end as column_name_jp
  , case
      when regexp_like(table_name, '^ps_tbl__attr_') then coalesce(attribute_group, '未分類')
      else '-'
    end as attribute_group
  , ordinal_position
  , no
from
  information_schema.columns
  inner join ${ps.cnfg_raw} using (table_name, column_name)
where
  table_schema = '${td.database}'
  and regexp_like(table_name, '^ps_tbl__(mstr|attr|bhvr)_')
  and column_name != 'time'
order by
  no
