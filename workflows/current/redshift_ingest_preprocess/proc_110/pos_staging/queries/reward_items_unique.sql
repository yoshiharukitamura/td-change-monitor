-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.reward_items
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , reward_category_id
  , unit
  , price_type
  , display_style
  , name
  , code
  , value
  , sort_order
  , sort_order_coupon
  , receipt_name
  , is_printed_on_receipt
  , is_applicable_to_total_number_of_treatment_minutes
  , min_of_total_treatment_minutes
  , max_of_total_treatment_minutes
  , is_able_to_be_used_in_combination_of_rewards
  , is_used_as_app_coupon
  , is_displayed_in_app
  , is_public
  , distribution_start_datetime
  , end_date_of_validity
  , image_file_name
  , terms_of_use_per_coupon
  , target
  , gender
  , start_age
  , end_age
  , number_of_visits
  , number_of_visits_operator
  , is_birthday
  , number_of_days_of_application_before_birthday
  , is_birth_month
  , number_of_days_of_application_before_first_day_of_birth_month
  , last_login_start
  , last_login_end
  , registered_date_start
  , registered_date_end
  , available_period_of_time_start
  , available_period_of_time_end
  , lapsed_days_from_last_visit
  , lapsed_days_from_last_visit_operator
  , number_of_days_of_validity_from_last_visit
  , type_of_sharing_discount
  , percentage_of_sharing_discount_for_therapist
  , if_rounding_up_or_down_ones_place
  , amount_of_sharing_discount_for_therapist
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.reward_items AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
