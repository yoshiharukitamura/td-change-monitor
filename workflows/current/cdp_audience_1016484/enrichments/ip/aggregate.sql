-- [TD TRACING] CDP: Audience/Enrichment
-- CDP: Audience: IP: audience/enrichments/ip/aggregate.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  cast(conv(substr(${join_column_name},1,2),16,10) as bigint)*3600 div 32 AS time,
  ${join_column_name},
  MAX(`timestamp`) AS `timestamp`,
  TD_LAST(td_ip, `timestamp`) AS td_ip,
  TD_LAST(td_country_name, `timestamp`) AS td_country_name,
  TD_LAST(td_ip_city_name, `timestamp`) AS td_ip_city_name,
  TD_LAST(td_ip_city_latitude, `timestamp`) AS td_ip_city_latitude,
  TD_LAST(td_ip_city_longitude, `timestamp`) AS td_ip_city_longitude,
  TD_LAST(td_ip_city_metro_code, `timestamp`) AS td_ip_city_metro_code,
  TD_LAST(td_ip_city_time_zone, `timestamp`) AS td_ip_city_time_zone,
  TD_LAST(td_ip_city_postal_code, `timestamp`) AS td_ip_city_postal_code,
  TD_LAST(td_ip_least_specific_subdivision_name, `timestamp`) AS td_ip_least_specific_subdivision_name,
  TD_LAST(td_ip_most_specific_subdivision_name, `timestamp`) AS td_ip_most_specific_subdivision_name,
  TD_LAST(td_ip_subdivision_names, `timestamp`) AS td_ip_subdivision_names,
  TD_LAST(td_ip_connection_type, `timestamp`) AS td_ip_connection_type,
  TD_LAST(td_ip_domain, `timestamp`) AS td_ip_domain
FROM (
  ${JSON.parse(http.last_content)["enrichments"]["ip"]["behaviors"].join('|').replace(/([^\|]+)/g, 'SELECT '+join_column_name+', `timestamp`, td_ip, td_country_name, td_ip_city_name, td_ip_city_latitude, td_ip_city_longitude, td_ip_city_metro_code, td_ip_city_time_zone, td_ip_city_postal_code, td_ip_least_specific_subdivision_name, td_ip_most_specific_subdivision_name, td_ip_subdivision_names, td_ip_connection_type, td_ip_domain FROM $1').split('|').join("\nUNION ALL\n")}
) t
GROUP BY ${join_column_name}
