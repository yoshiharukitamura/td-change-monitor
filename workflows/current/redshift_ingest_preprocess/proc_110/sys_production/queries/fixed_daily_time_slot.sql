-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  fixed_daily_time_slot_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.fixed_daily_time_slot
GROUP BY
  fixed_daily_time_slot_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.fixed_daily_time_slot_id
  , therapist_id
  , property_id
  , TD_TIME_FORMAT(TD_TIME_PARSE("date", 'JST'), 'yyyy-MM-dd', 'JST') AS "date"
  , start_time
  , end_time
  , break_start_time
  , break_end_time
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS registered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.updated_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS updated_datetime
  , deleted
FROM
  l0_sys_production.fixed_daily_time_slot AS P_02
JOIN
  P_01 ON P_01.fixed_daily_time_slot_id = P_02.fixed_daily_time_slot_id AND P_01.updated_datetime = P_02.updated_datetime
