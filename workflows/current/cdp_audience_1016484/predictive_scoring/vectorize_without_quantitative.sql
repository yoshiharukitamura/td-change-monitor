-- [TD TRACING] CDP: Audience/PredictiveScoring
-- CDP: Audience: Predictive Scoring: audience/predictive_scoring/vectorize_without_quantitative.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  time,
  ${join_column_name},
  array_concat(
    array('bias'),
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_array_as_column_names"].length == 0 ? '' : (JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_array_as_column_names"].join(","))}
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_array_as_column_names"].length > 0 && JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_as_column_names"].length > 0 ? ',' : ''}
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_as_column_names"].length == 0 ? '' : ("categorical_features(\narray(" + JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_as_column_names"].join('|').replace(/([^\|]+)/g, "'$1'").split('|').join(",\n") + "),\n" + JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_as_column_names"].join(",\n") + "\n)")}
  ) AS features
FROM
  cdp_tmp_predictive_score_${predictive_segment_id}_samples
