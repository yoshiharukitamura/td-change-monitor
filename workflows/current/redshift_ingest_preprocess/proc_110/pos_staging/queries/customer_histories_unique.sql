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
  , last_purchase_of_charge_point
  , current_charge_point
  , expiration_date_of_charge_point
  , current_bonus_point
  , expiration_date_of_bonus_point
  , last_treatment_date
  , availability_of_point_consumption
  , whether_customer_info_detail_is_satisfied
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.customer_histories AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
