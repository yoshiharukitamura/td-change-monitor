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
  , TD_TIME_FORMAT(TD_TIME_PARSE(reset_password_date, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS reset_password_date
  , reset_password_key
  , reset_password_device
  , TD_TIME_FORMAT(TD_TIME_PARSE(last_login, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS last_login
  , TD_TIME_FORMAT(TD_TIME_PARSE(last_login_app, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS last_login_app
  , TD_TIME_FORMAT(TD_TIME_PARSE(created_app, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created_app
  , push_noti
  , mailflg
  , TD_TIME_FORMAT(TD_TIME_PARSE(modified_batch, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified_batch
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , is_login_app
  , deleted
  , deleted_date
FROM
  l0_web_app_production.customers AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
