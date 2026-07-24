-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  neighborhood_property_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.neighborhood_shop
GROUP BY
  neighborhood_property_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.neighborhood_property_id
  , property_id
  , target_property_id
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS registered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.updated_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS updated_datetime
  , deleted
FROM
  l0_sys_production.neighborhood_shop AS P_02
JOIN
  P_01 ON P_01.neighborhood_property_id = P_02.neighborhood_property_id AND P_01.updated_datetime = P_02.updated_datetime
