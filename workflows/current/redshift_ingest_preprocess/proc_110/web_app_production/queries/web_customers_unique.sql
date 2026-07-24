-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_web_app_production.customers
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , dtb_customer_id
  , email
  , phone_no
  , sms_phone_no
  , pref_id
  , city
  , street
  , password
  , activation_key
  , activation_expiration
  , activation_sms_key
  , activation_sms_expiration
  , activated
  , activated_from
  , reset_password_date
  , reset_password_key
  , reset_password_device
  , last_login
  , last_login_app
  , created_app
  , push_noti
  , mailflg
  , modified_batch
  , created
  , P_02.modified
  , is_login_app
  , deleted
  , deleted_date
FROM
  l0_web_app_production.customers AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
