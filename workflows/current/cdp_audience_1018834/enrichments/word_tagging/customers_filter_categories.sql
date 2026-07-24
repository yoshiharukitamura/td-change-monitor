-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/customers_filter_categories.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH category_normalizer AS (
  SELECT
    ${join_column_name},
    sum(s_score) AS l1_normalizer,
    max(s_score) AS max_s_score
  FROM
    cdp_tmp_word_tagging_${behavior}_customers_categories_all
  WHERE
    parent_category IS ${parent_category_is}
  GROUP BY
    ${join_column_name}
)
-- DIGDAG_INSERT_LINE
SELECT
  t1.${join_column_name},
  t1.category,
  t1.parent_category,
  t1.s_score / t2.l1_normalizer AS category_score
FROM
  cdp_tmp_word_tagging_${behavior}_customers_categories_all t1
JOIN
  category_normalizer t2
  ON t1.${join_column_name} = t2.${join_column_name}
WHERE
  t1.parent_category IS ${parent_category_is}
  AND (t1.s_score / t2.l1_normalizer) >= (t2.max_s_score / t2.l1_normalizer * 0.8) -- prob >= threshold
