-- [TD TRACING] CDP: Audience/Enrichment
-- CDP: Audience: td-js-sdk: audience/enrichments/td_js_sdk/aggregate.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  cast(conv(substr(${join_column_name},1,2),16,10) as bigint)*3600 div 32 AS time,
  ${join_column_name},
  from_unixtime(MAX(`timestamp`), 'yyyy-MM-dd') AS td_last_access_date
FROM (
  ${JSON.parse(http.last_content)["enrichments"]["td_js_sdk"]["behaviors"].join('|').replace(/([^\|]+)/g, 'SELECT '+join_column_name+', `timestamp` FROM $1').split('|').join("\nUNION ALL\n")}
) t
GROUP BY ${join_column_name}
