-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  monthly_reward_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.monthly_reward
GROUP BY
  monthly_reward_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.monthly_reward_id
  , monthly_reward_summary_id
  , property_id
  , shop_no
  , facilities_usage_time
  , facilities_reward_tax_inc
  , facilities_reward_tax
  , work_time
  , work_time_traning
  , traning_time_reward_tax_incl
  , training_time_reward_tax
  , work_time_reward_tax_incl
  , work_time_reward_tax
  , min_work_time_reward_tax_incl
  , min_work_time_reward_tax
  , appoint_fee_tax_incl
  , appoint_fee_tax
  , option_tax_incl
  , option_tax
  , sales_charge_tax_incl
  , sales_charge_tax
  , sub_task_commission_tax_incl
  , sub_task_commission_tax
  , materials_fee_tax_incl
  , materials_fee_tax
  , facilities_fee_tax_incl
  , facilities_fee_tax
  , min_facilities_fee_tax_incl
  , min_facilities_fee_tax
  , risk_fee_tax_incl
  , risk_fee_tax
  , insurance_fee_tax_incl
  , insurance_fee_tax
  , peak_time_additional_reward_tax_incl
  , peak_time_additional_reward_tax
  , peak_time_determination_target_flag
  , other_additional_reward_tax_incl
  , other_additional_reward_tax
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS registered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.updated_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS updated_datetime
  , deleted
FROM
  l0_sys_production.monthly_reward AS P_02
JOIN
  P_01 ON P_01.monthly_reward_id = P_02.monthly_reward_id AND P_01.updated_datetime = P_02.updated_datetime
