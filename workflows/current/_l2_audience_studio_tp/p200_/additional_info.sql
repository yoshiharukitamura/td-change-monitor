select
  cast(substr(table_name, length(table_name)-1, 2) as int)*1000+ordinal_position
  , '_l2_audience_studio_tp' as parent_segment_name
  , 'セラピストコミュニケーション基盤' as description
  , table_name
  , table_name as table_name_jp
  , column_name
  , column_name as column_name_jp
  , replace(table_name, 'ps_tbl__attr_', '') as attribute_group
from
  information_schema.columns
where
  table_schema = '_l2_audience_studio_tp'
  and regexp_like(table_name, '^ps_tbl__attr_custom_list_.*')
  and column_name != 'time'
order by 
  1
