-- [TD TRACING] CDP: Audience/PredictiveScoring
-- CDP: Audience: Predictive Scoring: audience/predictive_scoring/add_train_label.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  coalesce(from_base(substr(coalesce(t1.${join_column_name}, t2.${join_column_name}),1,2),16)*3600/32,0) AS time,
  coalesce(t1.${join_column_name}, t2.${join_column_name}) AS ${join_column_name},
  IF(
    t1.${join_column_name} IS NOT NULL,
    t1.td_predictive_score_${predictive_segment_id},
    NULL
  ) AS td_predictive_score_${predictive_segment_id},
  IF(
    t2.${join_column_name} IS NOT NULL,
    1,
    NULL
  ) AS td_predictive_score_${predictive_segment_id}_train
FROM
  cdp_tmp_predictive_score_${predictive_segment_id} t1
FULL JOIN (
    -- customers who were used for training
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["base_segment_query"].replaceAll('"' + matrix_database_name + '"."' + matrix_customers_table_name + '"', '"' + matrix_database_name + '"."' + customers_table_name + '"')}
  ) t2
  ON t1.${join_column_name} = t2.${join_column_name}
