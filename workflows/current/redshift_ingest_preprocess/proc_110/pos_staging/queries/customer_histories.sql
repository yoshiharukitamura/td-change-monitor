-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.customer_histories
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , customer_id
  , customer_name
  , members_card_no
  , number_of_visits
  , TD_TIME_FORMAT(TD_TIME_PARSE(last_purchase_of_charge_point, 'JST'), 'yyyy-MM-dd', 'JST') AS last_purchase_of_charge_point
  , current_charge_point
  , TD_TIME_FORMAT(TD_TIME_PARSE(expiration_date_of_charge_point, 'JST'), 'yyyy-MM-dd', 'JST') AS expiration_date_of_charge_point
  , current_bonus_point
  , TD_TIME_FORMAT(TD_TIME_PARSE(expiration_date_of_bonus_point, 'JST'), 'yyyy-MM-dd', 'JST') AS expiration_date_of_bonus_point
  , TD_TIME_FORMAT(TD_TIME_PARSE(last_treatment_date, 'JST'), 'yyyy-MM-dd', 'JST') AS last_treatment_date
  , availability_of_point_consumption
  , whether_customer_info_detail_is_satisfied
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.customer_histories AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
