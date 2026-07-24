-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  monthly_reward_summary_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.monthly_reward_summary
GROUP BY
  monthly_reward_summary_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.monthly_reward_summary_id
  , therapist_id
  , yyyymm
  , reward_type
  , guaranteed_minimum_occur_flag
  , transfer_date
  , status
  , invalid_flag
  , monthly_job_flag
  , peak_time_target_flag
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS registered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.updated_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS updated_datetime
  , deleted
FROM
  l0_sys_production.monthly_reward_summary AS P_02
JOIN
  P_01 ON P_01.monthly_reward_summary_id = P_02.monthly_reward_summary_id AND P_01.updated_datetime = P_02.updated_datetime
