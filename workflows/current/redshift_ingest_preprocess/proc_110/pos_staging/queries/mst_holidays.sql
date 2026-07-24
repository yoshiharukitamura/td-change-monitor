-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.mst_holidays
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , type
  , TD_TIME_FORMAT(TD_TIME_PARSE(target_date, 'JST'), 'yyyy-MM-dd', 'JST') AS target_date
  , name
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.mst_holidays AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
