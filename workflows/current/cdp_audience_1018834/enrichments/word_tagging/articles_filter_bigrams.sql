-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/articles_filter_bigrams.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH uni AS (
  SELECT
    article_id,
    word
  FROM
    cdp_tmp_word_tagging_${behavior}_articles_tokens
  WHERE
    unigram = 1
),
bi AS (
  SELECT
    article_id,
    word
  FROM
    cdp_tmp_word_tagging_${behavior}_articles_tokens
  WHERE
    unigram = 0
)
-- DIGDAG_INSERT_LINE
SELECT article_id, word FROM uni
UNION ALL
SELECT article_id, word FROM bi
WHERE bi.word IN (SELECT DISTINCT word FROM cdp_tmp_word_tagging_category_mapping_en WHERE instr(word, ' ') > 0)
