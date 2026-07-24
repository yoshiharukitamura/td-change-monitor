-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.customers
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , members_card_no
  , name
  , name_full
  , password
  , gender
  , TD_TIME_FORMAT(TD_TIME_PARSE(birth_date, 'JST'), 'yyyy-MM-dd', 'JST') AS birth_date
  , job_id
  , phone_no
  , phone_no2
  , zip_code1
  , zip_code2
  , pref_id
  , city
  , street
  , email
  , email2
  , mail_magazine
  , email_existing
  , count_of_product_sales
  , price_of_product_sales
  , registration_route
  , referral_customer_id
  , remarks
  , shop_id_where_visited_first_time
  , is_not_sent_to_core
  , is_app_user
  , is_senior_member
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deactivated
  , TD_TIME_FORMAT(TD_TIME_PARSE(deactivated_date, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS deactivated_date
  , deleted
  , deleted_date
FROM
  l0_pos_staging.customers AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
