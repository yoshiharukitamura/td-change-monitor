-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/articles_keywords.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
WITH tf AS (
  SELECT
    article_id,
    word,
    freq
  FROM (
    SELECT
      article_id,
      tf(word) AS word2freq
    FROM
      cdp_tmp_word_tagging_${behavior}_articles_tokens
    GROUP BY
      article_id
  ) t
  LATERAL VIEW explode(word2freq) t2 AS word, freq
),
df AS (
  SELECT
    word,
    count(1) AS cnt -- number of articles which contain the word
  FROM (
    SELECT
      word,
      article_id
    FROM
      cdp_tmp_word_tagging_${behavior}_articles_tokens
    GROUP BY
      word,
      article_id
  ) t
  GROUP BY
    word
),
article_keyword AS (
  SELECT
    tf.article_id,
    tf.word,
    tfidf(tf.freq, df.cnt, ${td.last_results.n_article}) AS tfidf
  FROM
    tf
  JOIN
    df
    ON tf.word = df.word
  WHERE
    df.cnt >= 2
    AND df.cnt <= ${Math.max(100000, td.last_results.n_article / 2)} -- ignore too common words
),
topk as (
  -- This CTE is required to avoid CDP-1668
  SELECT
    each_top_k(
      20, article_id, tfidf,
      article_id, word
    ) AS (rank, score, article_id, word)
  FROM (
    SELECT
      article_id,
      word,
      tfidf
    FROM
      article_keyword
    CLUSTER BY
      article_id
  ) t
)
-- DIGDAG_INSERT_LINE
select
  rank, score, article_id, word
from
  topk
