-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.order_details
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , order_id
  , parent_order_detail_id
  , priority
  , is_necessary_to_add_relation_with_treatment_product
  , category_id
  , category_name
  , mst_product_id
  , product_name
  , receipt_name
  , order_added_timing
  , treatment_minutes
  , price_type
  , sales_price
  , quantity
  , consumption_tax
  , sub_total
  , basis_of_additional_bonus_point
  , additional_bonus_point
  , additional_charge_point
  , amount_of_reward_for_therapist
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.order_details AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
