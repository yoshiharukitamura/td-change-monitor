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
    , rate
  , comment
  , answer1
  , answer2
  , answer3
    , question_review_1
    , answer_review_1
    , question_review_2
    , answer_review_2
    , question_review_3
    , answer_review_3
    , question_review_4
    , answer_review_4
    , question_review_5
    , answer_review_5
  , is_confirmed
  , is_display_comment
  , is_approved_by_user
    , order_id
  , created
  , P_02.modified
  , deleted
  , deleted_date
    , is_review_app
FROM
  l0_web_app_production.reviews AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
