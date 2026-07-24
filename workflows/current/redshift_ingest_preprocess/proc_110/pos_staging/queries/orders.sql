-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.orders
GROUP BY
  id
),

akaden AS (
SELECT
  original_order_id
FROM
  l0_pos_staging.orders
WHERE
  TD_TIME_RANGE(time, null, td_scheduled_time(), 'JST')
  and order_type = 2
GROUP BY
  original_order_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , mst_shop_id
  , unique_order_id
  , customer_id
  , customer_name
  , customer_members_card_no
  , order_type
  , payment_type
  , member_type
  , status
  , is_canceled_when_closing_shop
  , cancel_reason
  , P_02.original_order_id
  , parent_order_id
  , reservation_id
  , TD_TIME_FORMAT(TD_TIME_PARSE(order_received_date, 'JST'), 'yyyy-MM-dd', 'JST') AS order_received_date
  , TD_TIME_FORMAT(TD_TIME_PARSE(order_received_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS order_received_datetime
  , total_amount_of_treatment_minutes
  , TD_TIME_FORMAT(TD_TIME_PARSE(treatment_start_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS treatment_start_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(treatment_end_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS treatment_end_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(purchased_date, 'JST'), 'yyyy-MM-dd', 'JST') AS purchased_date
  , TD_TIME_FORMAT(TD_TIME_PARSE(purchased_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS purchased_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_business_date, 'JST'), 'yyyy-MM-dd', 'JST') AS registered_business_date
  , total_number_of_products
  , total_amount_of_nomination_fee
  , total_reward_amount_of_price
  , subtotal_amount_of_price
  , total_amount_of_price
  , total_tax
  , received_amount
  , amount_of_cash_payment
  , payment_type_id
  , cashless_payment_service_name
  , amount_of_cashless_payment
  , amount_of_difference_of_cashless_payment
  , paygate_order_id
  , terminal_sequence
  , credit_card_no
  , used_charge_point
  , used_bonus_point
  , old_gift_card
  , amount_of_used_old_gift_card
  , change
  , birthday_point
  , total_additional_charge_point
  , total_additional_bonus_point
  , additional_bonus_point_for_stamp_rally
  , balance_of_charge_point
  , TD_TIME_FORMAT(TD_TIME_PARSE(expiration_date_of_charge_point, 'JST'), 'yyyy-MM-dd', 'JST') AS expiration_date_of_charge_point
  , balance_of_bonus_point
  , TD_TIME_FORMAT(TD_TIME_PARSE(expiration_date_of_bonus_point, 'JST'), 'yyyy-MM-dd', 'JST') AS expiration_date_of_bonus_point
  , shop_name
  , shop_telephone_no
  , gender
  , phone_no
  , email
  , purchased_customer_id
  , purchased_customer_name
  , purchased_customer_members_card_no
  , if_experienced_serious_injury
  , injured_date
  , sign_image_file_name
  , pandemic_virus_signature_images
  , accepted_therapist_id
  , accepted_therapist_name
  , purchased_therapist_id
  , purchased_therapist_name
  , cancel_therapist_id
  , cancel_therapist_name
  , cancel_datetime
  , if_body_pillow_is_used
  , if_customer_does_not_feel_uncomfortable_and_pain
  , is_updated_different_month
  , is_registered_in_admin
  , TD_TIME_FORMAT(TD_TIME_PARSE(visit_date_before_last_time, 'JST'), 'yyyy-MM-dd', 'JST') AS visit_date_before_last_time
  , therapist_name_who_treated_before_last_time
  , TD_TIME_FORMAT(TD_TIME_PARSE(visit_date_last_time, 'JST'), 'yyyy-MM-dd', 'JST') AS visit_date_last_time
  , therapist_name_who_treated_last_time
  , therapist_name_who_treated_this_time
  , remarks
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.orders AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
LEFT JOIN akaden on P_01.id = akaden.original_order_id
where
  TD_TIME_RANGE(time, null, td_scheduled_time(), 'jst')
  AND P_02.order_type = 1
  and akaden.original_order_id IS NULL
  and treatment_start_datetime < treatment_end_datetime
  and therapist_name_who_treated_this_time != 'トレーナー施術用'
