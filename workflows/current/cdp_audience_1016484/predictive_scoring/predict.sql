-- [TD TRACING] CDP: Audience/PredictiveScoring
-- CDP: Audience: Predictive Scoring: audience/predictive_scoring/predict.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH logress_samples_exploded AS (
  SELECT
    time,
    ${join_column_name},
    extract_feature(fv) AS feature,
    extract_weight(fv) AS value
  FROM
    cdp_tmp_predictive_score_${predictive_segment_id}_samples t1
  LATERAL VIEW explode(features) t2 AS fv
)
-- DIGDAG_INSERT_LINE
SELECT
  time,
  ${join_column_name},
  -- use calibrated probability to prevent negative effect of over-sampling
  (p / ${td.last_results.pos_oversample_rate}) / (p / ${td.last_results.pos_oversample_rate} + (1.0 - p) / ${td.last_results.neg_oversample_rate}) * 100.0 AS td_predictive_score_${predictive_segment_id}
FROM (
  SELECT
    cast(conv(substr(t1.${join_column_name},1,2),16,10) as bigint)*3600 div 32 AS time,
    t1.${join_column_name},
    sigmoid( sum(p1.weight * t1.value) ) AS p
  FROM
    logress_samples_exploded t1
  LEFT OUTER JOIN
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["model_table_name"]} p1
    ON (t1.feature = p1.feature)
  GROUP BY
    t1.${join_column_name}
) score
