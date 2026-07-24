-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/customers_map_all_categories.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH joined AS (
  SELECT
    t1.${join_column_name},
    t1.tag_score,
    t2.category,
    t2.parent_category,
    t2.score
  FROM
    cdp_tmp_word_tagging_${behavior} t1
  JOIN
    -- ja: use `tag` directly
    -- en: singularize `tag` before joining with the mapping table
    cdp_tmp_word_tagging_category_mapping_${td.last_results.lang} t2
    ON ${td.last_results.lang.replace('ja', 't1.tag').replace('en', 'singularize(t1.tag)')} = t2.word
)
-- DIGDAG_INSERT_LINE
SELECT
  ${join_column_name},
  category,
  parent_category,
  sum(tag_score * score) AS s_score
FROM
  joined
GROUP BY
  ${join_column_name},
  category,
  parent_category
