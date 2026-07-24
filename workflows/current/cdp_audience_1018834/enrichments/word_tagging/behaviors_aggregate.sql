-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/behaviors_aggregate.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH stacked AS (
  -- Stack all behaviors (behavior_1, behavior_2, ..., behavior_n) as follows:
  -- > SELECT tag,  NULL,     NULL,           NULL,         NULL                FROM behavior_1_tag
  -- > UNION ALL
  -- > SELECT NULL, category, category_score, sub_category, sub_category_score  FROM behavior_1_category
  -- > UNION ALL
  -- > ...
  -- > UNION ALL
  -- > SELECT tag,  NULL,     NULL,           NULL,         NULL                FROM behavior_n_tag
  -- > UNION ALL
  -- > SELECT NULL, category, category_score, sub_category, sub_category_score  FROM behavior_n_category
  ${JSON.parse(http.last_content)["enrichments"]["word_tagging"]["behaviors"].join('|').replace(/([^\|]+)/g, 'SELECT ' + join_column_name + ', tag, NULL AS category, NULL AS category_score, NULL AS sub_category, NULL AS sub_category_score FROM cdp_tmp_word_tagging_$1_customers_tags|SELECT ' + join_column_name + ', NULL AS tag, category, category_score, sub_category, sub_category_score FROM cdp_tmp_word_tagging_$1_customers_categories').split('|').join("\nUNION ALL\n")}
)
-- DIGDAG_INSERT_LINE
SELECT
  ${join_column_name},
  tags,
  IF(
    SIZE(category2score) = 0,
    NULL,
    map_keys(category2score)
  ) AS categories,
  IF(
    SIZE(category2score) = 0,
    NULL,
    map_values(category2score)
  ) AS category_scores,
  IF(
    SIZE(sub_category2score) = 0,
    NULL,
    map_keys(sub_category2score)
  ) AS sub_categories,
  IF(
    SIZE(sub_category2score) = 0,
    NULL,
    map_values(sub_category2score)
  ) AS sub_category_scores
FROM (
  SELECT
    ${join_column_name},
    collect_set(tag) AS tags,
    to_ordered_map(category, category_score) AS category2score,
    to_ordered_map(sub_category, sub_category_score) AS sub_category2score
  FROM
    stacked
  GROUP BY
    ${join_column_name}
) t
