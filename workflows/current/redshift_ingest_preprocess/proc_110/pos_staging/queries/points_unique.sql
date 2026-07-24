-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.points
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , mst_shop_id
  , customer_id
  , order_detail_id
  , registered_date
  , point_type
  , remarks
  , point_status
  , is_public
  , history_point
  , current_point
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.points AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
