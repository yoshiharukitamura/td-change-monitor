with mstr as (
  select distinct
    '{"parentDatabaseName": "' || database_name || '", "parentTableName": "' || table_name || '"}' as scr_mstr
  from
    ${database_name}.${table_name}
  where
    table_type_name = 'Master Table'
    and parent_segment_name = '${parent_segment_name}'
)
, attr as (
  select
    array_join(array_agg(scr), ', ') as scr_attr
  from (
      select
        '{"audienceId": "${audience_id}", "name": "' || column_name_jp || '", "type": "' || data_type || '", "parentDatabaseName": "' || database_name || '", "parentTableName": "' || table_name ||'", "parentColumn": "'|| column_name ||'", "parentKey": "mstr__id", "foreignKey": "mstr__id", "usedBySegmentInsight": true, "groupingName": "'|| attribute_group ||'"}' as scr
      from
        ${database_name}.${table_name}
      where
        table_type_name = 'Attribute Table'
        and column_name != 'mstr__id'
        and parent_segment_name = '${parent_segment_name}'
      order by
        no
    )
)
, bhvr_tmp as (
  select
    database_name
    , table_name
    , table_name_jp
    , array_join(array_agg('{"name": "'||column_name_jp||'", "'||data_type||'": "string", "parentColumn": "'||column_name||'"}' order by no), ', ') as scr
    , min(no) as no
  from
    ${database_name}.${table_name}
  where
    table_type_name = 'Behavior Table'
    and parent_segment_name = '${parent_segment_name}'
  group by
    database_name
    , table_name
    , table_name_jp
)
, bhvr as (
  select
    array_join(array_agg(scr), ', ') as scr_bhvr
  from (
      select
        '{"audienceId": "${audience_id}", "name": "' || table_name_jp || '", "parentDatabaseName": "' ||database_name|| '", "parentTableName": "' ||table_name|| '", "parentKey": "mstr__id", "foreignKey": "mstr__id", "schema": [' ||scr|| ']}' as scr
      from
        bhvr_tmp
      order by
        no
    )
)

select
  *
from
  mstr
  left join attr on 1=1
  left join bhvr on 1=1
