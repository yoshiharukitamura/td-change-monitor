-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/articles_detect_language.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  ${td.last_results.n_article} AS n_article, -- carrying over current "last_results"
  IF(weight_ja > 0.1, 'ja', 'en') AS lang -- if more than 10% of pre-sampled articles include Japanese character, word tagging assumes the behavior's language is Japanese
FROM (
  SELECT
    sum(IF(regexp_like(content, '[ぁ-んァ-ヶ]'), 1, 0)) / cast(count(1) AS double) AS weight_ja
  FROM (
    -- randomly sample 1000 contents of articles
    SELECT content FROM cdp_tmp_word_tagging_${behavior} LIMIT 1000
  ) samples
) weight
