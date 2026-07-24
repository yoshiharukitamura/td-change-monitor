select
  '${data_catalog}' as data_catalog
  , '${td.each.table_schema}' as table_schema
  , '${td.each.table_name}' as table_name
  , '${td.last_results.min_time}' as min_time
  , '${td.last_results.max_time}' as max_time
  , try_cast(format('%,d', ${td.last_results.records}) as varchar) as records
  , try_cast(${td.each.ordinal_position} as varchar) as no
  , '${td.each.column_name}' as column_name
  , '${td.each.data_type}' as data_type
  , min(case
      when ${td.each.records} = 0 then ''
      ${(td.each.data_type.match(/array/g))?"else json_format(cast("+td.each.column_name+" as json))":""}
      ${(td.each.data_type.match(/float|double/g))?"else cast(cast("+td.each.column_name+" as decimal(38,5)) as varchar)":""}
      ${(!td.each.data_type.match(/array|float|double/g))?"else cast("+td.each.column_name+" as varchar)":""}
    end) as min_value
  , max(case
      when ${td.each.records} = 0 then ''
      ${(td.each.data_type.match(/array/g))?"else json_format(try_cast("+td.each.column_name+" as json))":""}
      ${(td.each.data_type.match(/float|double/g))?"else try_cast(try_cast("+td.each.column_name+" as decimal(38,5)) as varchar)":""}
      ${(!td.each.data_type.match(/array|float|double/g))?"else try_cast("+td.each.column_name+" as varchar)":""}
    end) as max_value
  , replace(try_cast(try_cast(
      count(if(length(coalesce(case
            when ${td.each.records} = 0 then ''
            ${(td.each.data_type.match(/array/g))?"else json_format(try_cast("+td.each.column_name+" as json))":""}
            ${(td.each.data_type.match(/float|double/g))?"else try_cast(try_cast("+td.each.column_name+" as decimal(38,5)) as varchar)":""}
            ${(!td.each.data_type.match(/array|float|double/g))?"else try_cast("+td.each.column_name+" as varchar)":""}
          end, ''))=0, 1, null)
        )/try_cast(nullif(count(1), 0) as double)*100
      as decimal(5,1)) as varchar)||'%', '.0%', '%') as null_blank
from
  ${td.each.table_schema}.${td.each.table_name}
where
  time between ${moment(td.last_results.max_time).subtract(7, 'd').unix()} and ${moment(td.last_results.max_time).unix()}
