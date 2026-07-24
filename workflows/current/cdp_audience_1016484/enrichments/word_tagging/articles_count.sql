-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/articles_count.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  approx_distinct(article_id) AS n_article
FROM
  cdp_tmp_word_tagging_${behavior}
