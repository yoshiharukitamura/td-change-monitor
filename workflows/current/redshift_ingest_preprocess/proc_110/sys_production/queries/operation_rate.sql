-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  therapist_operation_rate_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.operation_rate
GROUP BY
  therapist_operation_rate_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.therapist_operation_rate_id
  , property_id
  , TD_TIME_FORMAT(TD_TIME_PARSE(business_date, 'JST'), 'yyyy-MM-dd', 'JST') AS business_date
  , bed_num
  , num_of_therapist_9
  , num_of_frame_9
  , used_bed_rate_9
  , operation_rate_9
  , num_of_therapist_10
  , num_of_frame_10
  , used_bed_rate_10
  , operation_rate_10
  , num_of_therapist_11
  , num_of_frame_11
  , used_bed_rate_11
  , operation_rate_11
  , num_of_therapist_12
  , num_of_frame_12
  , used_bed_rate_12
  , operation_rate_12
  , num_of_therapist_13
  , num_of_frame_13
  , used_bed_rate_13
  , operation_rate_13
  , num_of_therapist_14
  , num_of_frame_14
  , used_bed_rate_14
  , operation_rate_14
  , num_of_therapist_15
  , num_of_frame_15
  , used_bed_rate_15
  , operation_rate_15
  , num_of_therapist_16
  , num_of_frame_16
  , used_bed_rate_16
  , operation_rate_16
  , num_of_therapist_17
  , num_of_frame_17
  , used_bed_rate_17
  , operation_rate_17
  , num_of_therapist_18
  , num_of_frame_18
  , used_bed_rate_18
  , operation_rate_18
  , num_of_therapist_19
  , num_of_frame_19
  , used_bed_rate_19
  , operation_rate_19
  , num_of_therapist_20
  , num_of_frame_20
  , used_bed_rate_20
  , operation_rate_20
  , num_of_therapist_21
  , num_of_frame_21
  , used_bed_rate_21
  , operation_rate_21
  , num_of_therapist_22
  , num_of_frame_22
  , used_bed_rate_22
  , operation_rate_22
  , num_of_therapist_23
  , num_of_frame_23
  , used_bed_rate_23
  , operation_rate_23
  , num_of_therapist_24
  , num_of_frame_24
  , used_bed_rate_24
  , operation_rate_24
  , num_of_therapist_25
  , num_of_frame_25
  , used_bed_rate_25
  , operation_rate_25
  , num_of_therapist_26
  , num_of_frame_26
  , used_bed_rate_26
  , operation_rate_26
  , num_of_therapist_27
  , num_of_frame_27
  , used_bed_rate_27
  , operation_rate_27
  , num_of_therapist_28
  , num_of_frame_28
  , used_bed_rate_28
  , operation_rate_28
  , num_of_therapist_29
  , num_of_frame_29
  , used_bed_rate_29
  , operation_rate_29
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS registered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.updated_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS updated_datetime
  , deleted
FROM
  l0_sys_production.operation_rate AS P_02
JOIN
  P_01 ON P_01.therapist_operation_rate_id = P_02.therapist_operation_rate_id AND P_01.updated_datetime = P_02.updated_datetime
