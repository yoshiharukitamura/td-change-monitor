-- [TD TRACING] CDP: Audience/PredictiveScoring
-- CDP: Audience: Predictive Scoring: audience/predictive_scoring/oversample_rate.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH label2cnt AS (
  SELECT
    map_agg(label, cnt) AS kv
  FROM (
    SELECT
      label,
      CAST(COUNT(1) AS double) AS cnt
    FROM
      cdp_predictive_segment_customers_${predictive_segment_id}
    GROUP BY
      label
  ) t
)
SELECT
  -- If % of minor samples is very small (less than 0.1%),
  -- amplify them so that at least 1% of samples are occupied by the minors.
  IF(element_at(kv, 1) / element_at(kv, 0) < 0.001, -- % of positive samples is less than 0.1%
     cast(floor(0.01 / (element_at(kv, 1) / element_at(kv, 0))) AS integer), 1) AS pos_oversample_rate,
  IF(element_at(kv, 0) / element_at(kv, 1) < 0.001, -- % of negative samples is less than 0.1%
     cast(floor(0.01 / (element_at(kv, 0) / element_at(kv, 1))) AS integer), 1) AS neg_oversample_rate
FROM
  label2cnt
