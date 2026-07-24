-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.order_detail_reward_items
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , order_detail_id
  , reward_item_id
  , name
  , unit
  , reward_item_value
  , consumption_tax
  , receipt_name
  , is_printed_on_receipt
  , mst_therapist_id_who_used_reward
  , amount_of_sharing_discount_for_therapist
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.order_detail_reward_items AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
