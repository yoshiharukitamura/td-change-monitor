-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.mst_shops
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id AS mst_shop_id
  , no
  , name
  , name_kana
  , logo_image_file_name
  , status
  , mst_area_id
  , pref_id
  , zip_code
  , city
  , street
  , telephone_no
  , fax_no
  , business_hour_start
  , business_hour_end
  , prepared_change
  , amount_of_points_given_to_introducer
  , free_content_for_receipt_1
  , free_content_for_receipt_2
  , is_not_sent_to_core
  , threshold_for_shop_vacancy
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.mst_shops AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
