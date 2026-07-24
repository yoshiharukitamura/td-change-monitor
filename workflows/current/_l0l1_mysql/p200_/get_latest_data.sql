${(tbl.pk)?"with latest as (select " + tbl.pk + ", max(time) as time from " + in_database.database + "." + tbl.name + " group by " + tbl.pk + ")":""}
${(!tbl.pk)?"with latest as (select max(time) as time from " + in_database.database + "." + tbl.name + ")":""}

select distinct
   *
  ${(tbl.pk)? ", 'mysql_" + tbl.incremental_by + "' as time_means":""}
  ${(!tbl.pk)? ", 'mysql_load_time' as time_means":""}
from 
  ${in_database.database}.${tbl.name}
  ${(tbl.pk)?"inner join latest using (" + tbl.pk + ", time)":"inner join latest using (time)"}
  ${(!tbl.pk)?"inner join latest using (time)":""}