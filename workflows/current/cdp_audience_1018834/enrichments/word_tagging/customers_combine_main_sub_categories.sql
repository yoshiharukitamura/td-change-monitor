-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/customers_combine_main_sub_categories.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  t1.${join_column_name},
  t1.category AS category,
  t1.category_score AS category_score,
  t2.category AS sub_category,
  t2.category_score AS sub_category_score
FROM
  cdp_tmp_word_tagging_${behavior}_customers_categories_main t1
LEFT JOIN
  cdp_tmp_word_tagging_${behavior}_customers_categories_sub t2
  ON
    t1.${join_column_name} = t2.${join_column_name}
    AND t1.category = t2.parent_category
