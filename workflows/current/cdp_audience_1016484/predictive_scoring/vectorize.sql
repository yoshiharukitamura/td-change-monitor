-- [TD TRACING] CDP: Audience/PredictiveScoring
-- CDP: Audience: Predictive Scoring: audience/predictive_scoring/vectorize.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
-- @TD enable_cartesian_product:true
WITH minmax AS (
  -- In fact, we like to compute minmax on Presto
  -- and directly embed the values by using
  -- `td.last_results.min_...`.  However, since we
  -- have no way to express nested JS variable in
  -- .dig file like
  -- `column_names.replace(regexp, ... +
    -- td_last_results.min_$1 + ... `, this query
    -- computes minmax on Hive and CROSS JOIN with
    -- the original table.
  SELECT
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["quantitative_as_column_names"].join('|').replace(/([^\|]+)/g, 'min($1) AS min_$1, max($1) AS max_$1').split('|').join(",\n")}
  FROM
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["minmax_source_table_name"]}
)
-- DIGDAG_INSERT_LINE
SELECT
  time,
  ${join_column_name},
  array_concat(
    array('bias'),
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_array_as_column_names"].length == 0 ? '' : (JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_array_as_column_names"].join(",") + ",")}
    ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_as_column_names"].length == 0 ? '' : ("categorical_features(\narray(" + JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_as_column_names"].join('|').replace(/([^\|]+)/g, "'$1'").split('|').join(",\n") + "),\n" + JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["categorical_as_column_names"].join(",\n") + "\n),")}
    quantitative_features(
      array(
        ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["quantitative_as_column_names"].join('|').replace(/([^\|]+)/g, "'$1'").split('|').join(",\n")}
      ),
      ${JSON.parse(http.last_content)["predictive_segments"][predictive_segment_id]["rule"]["quantitative_as_column_names"].join('|').replace(/([^\|]+)/g, 'rescale($1, min_$1, max_$1)').split('|').join(",\n")}
    )
  ) AS features
FROM
  cdp_tmp_predictive_score_${predictive_segment_id}_samples
LEFT OUTER JOIN
  minmax t2
