-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_web_reservation_production.reservation_products
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , reservation_id
  , mst_product_id
  , price_type
  , app_member_course_price
  , card_member_course_price
  , non_member_course_price
  , senior_member_course_price
  , app_member_option_price
  , card_member_option_price
  , non_member_option_price
  , senior_member_option_price
  , amount_of_reward_for_therapist
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_web_reservation_production.reservation_products AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
