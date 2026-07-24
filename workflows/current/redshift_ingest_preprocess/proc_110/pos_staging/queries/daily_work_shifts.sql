-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.daily_work_shifts
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , mst_therapist_id
  , mst_shop_id
  , therapist_type
  , TD_TIME_FORMAT(TD_TIME_PARSE(target_date, 'JST'), 'yyyy-MM-dd', 'JST') AS target_date
  , TD_TIME_FORMAT(TD_TIME_PARSE(start_time, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS start_time
  , TD_TIME_FORMAT(TD_TIME_PARSE(end_time, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS end_time
  , tentative_leave_start_time
  , tentative_leave_end_time
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.daily_work_shifts AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
