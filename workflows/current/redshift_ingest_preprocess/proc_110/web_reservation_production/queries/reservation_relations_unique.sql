-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_web_reservation_production.reservation_relations
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , resource_timetable_id
  , reservation_id
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_web_reservation_production.reservation_relations AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
