-- [TD TRACING] CDP: Audience/WordTagging
-- CDP: Audience: Word Tagging: audience/enrichments/word_tagging/behavior_preprocess.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
SELECT
  ${join_column_name},
  concat(td_host, td_path) AS article_id,
  concat(
    -- remove site name which commonly occurs at the foot of page title
    regexp_replace(
      -- "(xxx)" is generally meaningless, accessory part of page title
      regexp_replace(
        td_title,
        '[(（].+?[)）]', ''
      ),
      '[|-] .+$', ''
    ),
    ' ',
    coalesce(td_description, '')
  ) AS content
FROM
  ${behavior}
WHERE
  td_title IS NOT NULL
  AND TD_TIME_RANGE(time, TD_TIME_ADD(TD_SCHEDULED_TIME(), '-90d'))
