-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_web_app_production.reviews
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , customer_id
  , order_detail_id
  , rank
  , comment
  , is_confirmed
  , is_display_comment
  , is_approved_by_user
  , answer1
  , answer2
  , answer3
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_web_app_production.reviews AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
