-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  therapist_daily_report_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.therapist_daily_report
GROUP BY
  therapist_daily_report_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.therapist_daily_report_id
  , therapist_id
  , TD_TIME_FORMAT(TD_TIME_PARSE(business_date, 'JST'), 'yyyy-MM-dd', 'JST') AS business_date
  , property_id
  , therapist_no
  , shop_no
  , TD_TIME_FORMAT(TD_TIME_PARSE(start_time, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS start_time
  , TD_TIME_FORMAT(TD_TIME_PARSE(end_time, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS end_time
  , break_time
  , sub_task_commission_tax_incl
  , sub_task_commission_tax
  , leaks_clocking_out
  , TD_TIME_FORMAT(TD_TIME_PARSE(info_change_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS info_change_datetimeregistered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS registered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.updated_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS updated_datetime
  , deleted
FROM
  l0_sys_production.therapist_daily_report AS P_02
JOIN
  P_01 ON P_01.therapist_daily_report_id = P_02.therapist_daily_report_id AND P_01.updated_datetime = P_02.updated_datetime
