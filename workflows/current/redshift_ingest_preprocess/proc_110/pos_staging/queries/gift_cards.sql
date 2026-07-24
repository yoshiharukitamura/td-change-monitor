-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.gift_cards
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , no
  , customer_id
  , order_detail_id
  , amount_of_points_charged
  , TD_TIME_FORMAT(TD_TIME_PARSE(purchased_date, 'JST'), 'yyyy-MM-dd', 'JST') AS purchased_date
  , purchased_shop_id
  , purchased_therapist_id
  , purchased_members_card_no
  , purchased_customer_name
  , TD_TIME_FORMAT(TD_TIME_PARSE(consumed_date, 'JST'), 'yyyy-MM-dd', 'JST') AS consumed_date
  , consumed_shop_id
  , consumed_therapist_id
  , consumed_customer_id
  , consumed_members_card_no
  , consumed_customer_name
  , is_consumed
  , is_expired
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.gift_cards AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
