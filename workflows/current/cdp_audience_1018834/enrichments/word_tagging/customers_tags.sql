-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/customers_tags.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH tag_top_k AS (
  SELECT
    each_top_k(
      20, ${join_column_name}, tag_score,
      ${join_column_name}, tag
    ) AS (rank, tag_score, ${join_column_name}, tag)
  FROM (
    SELECT
      ${join_column_name},
      tag,
      tag_score
    FROM cdp_tmp_word_tagging_${behavior}
    CLUSTER BY
      ${join_column_name}
  ) t
)
-- DIGDAG_INSERT_LINE
SELECT
  ${join_column_name},
  tag
FROM
  tag_top_k
