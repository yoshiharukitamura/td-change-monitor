-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_web_reservation_production.resource_timetables
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , daily_work_shift_id
  , mst_timetable_id
  , mst_reservation_resource_id
  , mst_shop_id
  , parent_resource_timetable_id
  , revision
  , start_time
  , end_time
  , working_date
  , status
  , last_reservable_time
  , last_reservable_kind
  , comment
  , early_arrival_time
  , max_treatment_minutes_of_last_reservation
  , created
  , P_02.modified
  , P_02.deleted
  , deleted_date
FROM
  l0_web_reservation_production.resource_timetables AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
