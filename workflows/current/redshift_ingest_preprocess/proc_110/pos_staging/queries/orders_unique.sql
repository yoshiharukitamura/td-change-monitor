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
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , unique_order_id
  , order_type
  , payment_type
  , member_type
  , status
  , is_canceled_when_closing_shop
  , cancel_reason
  , original_order_id
  , parent_order_id
  , reservation_id
  , order_received_date
  , order_received_datetime
  , total_amount_of_treatment_minutes
  , treatment_start_datetime
  , treatment_end_datetime
  , purchased_date
  , purchased_datetime
  , registered_business_date
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
  , expiration_date_of_charge_point
  , balance_of_bonus_point
  , expiration_date_of_bonus_point
  , mst_shop_id
  , shop_name
  , shop_telephone_no
  , customer_id
  , customer_name
  , customer_members_card_no
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
  , visit_date_before_last_time
  , therapist_name_who_treated_before_last_time
  , visit_date_last_time
  , therapist_name_who_treated_last_time
  , therapist_name_who_treated_this_time
  , remarks
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.orders AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
