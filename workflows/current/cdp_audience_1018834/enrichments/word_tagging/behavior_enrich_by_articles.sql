-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/behavior_enrich_by_articles.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  t1.${join_column_name},
  t2.word AS tag,
  sum(score) AS tag_score
FROM
  cdp_tmp_word_tagging_${behavior} t1
JOIN
  cdp_tmp_word_tagging_${behavior}_articles_keywords t2
  ON t1.article_id = t2.article_id
GROUP BY
  t1.${join_column_name},
  t2.word
