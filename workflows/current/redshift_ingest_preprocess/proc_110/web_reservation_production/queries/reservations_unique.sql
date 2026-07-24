-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_web_reservation_production.reservations
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , reservation_code
  , reservation_person_id
  , reservation_index
  , parent_reservation_id
  , status
  , reserved_from
  , start_time
  , end_time
  , interval_end_time
  , total_amount_of_price
  , mst_product_id
  , if_use_premium_mattress
  , designation_type
  , designation_fixed
  , mst_pressure_id
  , mst_conversation_id
  , remarks
  , if_experienced_serious_injury
  , injured_date
  , sign_image_file_name
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_web_reservation_production.reservations AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
