-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(created) AS created
FROM
  l0_pos_staging.reward_item_customers
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.created, 'JST') AS time
  , P_02.id
  , reward_item_id
  , customer_id
  , P_02.created
FROM
  l0_pos_staging.reward_item_customers AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.created = P_02.created
