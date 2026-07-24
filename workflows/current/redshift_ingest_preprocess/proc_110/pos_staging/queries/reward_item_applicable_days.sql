-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.reward_item_applicable_days
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , reward_item_id
  , days_of_week
  , TD_TIME_FORMAT(TD_TIME_PARSE(start_date, 'JST'), 'yyyy-MM-dd', 'JST') AS start_date
  , TD_TIME_FORMAT(TD_TIME_PARSE(end_date, 'JST'), 'yyyy-MM-dd', 'JST') AS end_date
  , max_number_of_uses
  , is_applicable_to_new_shop
  , is_applied_to_product
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.reward_item_applicable_days AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
