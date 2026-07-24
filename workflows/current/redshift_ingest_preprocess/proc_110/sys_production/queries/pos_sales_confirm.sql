-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  pos_sales_confirm_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.pos_sales_confirm
GROUP BY
  pos_sales_confirm_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.pos_sales_confirm_id
  , pos_sales_id
  , cash_over_short
  , monthly_mistake_calc
  , deposit_amount
  , monthly_deposit_difference
  , not_deposited_transfer_amount
  , hq_comment
  , status
  , TD_TIME_FORMAT(TD_TIME_PARSE(info_change_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS info_change_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS registered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.updated_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS updated_datetime
  , deleted
FROM
  l0_sys_production.pos_sales_confirm AS P_02
JOIN
  P_01 ON P_01.pos_sales_confirm_id = P_02.pos_sales_confirm_id AND P_01.updated_datetime = P_02.updated_datetime
