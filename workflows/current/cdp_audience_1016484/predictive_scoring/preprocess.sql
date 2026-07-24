-- [TD TRACING] CDP: Audience/PredictiveScoring
-- CDP: Audience: Predictive Scoring: audience/predictive_scoring/preprocess.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  "customers".time,
  "customers".${join_column_name},
  ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["preprocess"].join(",\n  ")}
FROM
  -- replacing "cdp_audience_xxx"."customers" with
  -- "cdp_audience_xxx"."cdp_tmp_(yyy_)customers" so segment query referrs
  -- latest, under-building customer data.
  ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["preprocess_from"].replaceAll('"' + matrix_database_name + '"."' + matrix_customers_table_name + '"', '"' + matrix_database_name + '"."' + customers_table_name + '"')}
