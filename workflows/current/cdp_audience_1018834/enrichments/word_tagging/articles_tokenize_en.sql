-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/articles_tokenize_en.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH article AS (
  SELECT
    article_id,
    td_last(content, time) AS content
  FROM
    cdp_tmp_word_tagging_${behavior}
  GROUP BY
    article_id
),
tokenized AS (
  SELECT
    article_id,
    ngram, -- e.g., "machine", "learning", "machine learning"
    split(ngram, ' ') AS ngram_words -- e.g., ["machine"], ["learning"], ["machine", "learning"]
  FROM
    article t1
    LATERAL VIEW explode(word_ngrams(tokenize(normalize_unicode(content, 'NFKC'), true), 1, 2)) t2 AS ngram -- create both uni- and bi-gram
)
-- DIGDAG_INSERT_LINE
SELECT
  article_id,
  ngram AS word,
  IF(size(ngram_words) = 1, 1, 0) AS unigram
FROM
  tokenized
WHERE ( -- filter out uni- or bi-gram which contains at least one meaningless word
    -- uni-gram
    size(ngram_words) = 1
    AND length(ngram_words[0]) > 2 AND ngram_words[0] RLIKE '^[a-zA-Z]+$' AND NOT is_stopword(ngram_words[0])
  ) OR (
    -- bi-gram
    size(ngram_words) = 2
    AND length(ngram_words[0]) > 2 AND ngram_words[0] RLIKE '^[a-zA-Z]+$' AND NOT is_stopword(ngram_words[0])
    AND length(ngram_words[1]) > 2 AND ngram_words[1] RLIKE '^[a-zA-Z]+$' AND NOT is_stopword(ngram_words[1])
  )
