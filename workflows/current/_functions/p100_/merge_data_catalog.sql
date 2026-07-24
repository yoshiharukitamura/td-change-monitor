with header as (
  select
    'table_schema' as "データベース名"
    , 'table_name' as "テーブル名（物理名）"
    , 'table_name_jp' as "テーブル名（論理名）"
    , 'min_time' as "timeカラムの最小値"
    , 'max_time' as "timeカラムの最大値"
    , 'records' as "累計レコード数"
    , 'no' as "#"
    , 'column_name' as "カラム名（物理名）"
    , 'column_name_jp' as "カラム名（論理名）"
    , 'data_type' as "データ型"
    , 'min_value' as "データの最小値-直近7日"
    , 'max_value' as "データの最大値-直近7日"
    , 'null_blank' as "NULL/BLANKの割合-直近7日"
    , 'description' as "特記事項・補足"
    , 'update_time' as "定義書の更新日時"
    , 0 as seq
)
, body as (
  select
    table_schema
    , table_name
    , table_name_jp
    , min_time
    , max_time
    , records
    , no
    , column_name
    , column_name_jp
    , data_type
    , min_value
    , max_value
    , null_blank
    , description
    , td_time_string(${session_unixtime}, 's!', 'jst') as update_time
    , row_number() over (order by table_schema, table_name, cast(no as bigint)) as seq
  from
    src_data_catalog_columns
    left join (
      select
        table_schema, table_name, column_name
        , table_name_jp, column_name_jp, description
      from
        ${data_catalog}
    ) using (table_schema, table_name, column_name)
  where
    data_catalog = '${data_catalog}'
)

select * from header
union all select * from body
