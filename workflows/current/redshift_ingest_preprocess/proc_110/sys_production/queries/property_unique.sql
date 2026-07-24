-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  property_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.property
GROUP BY
  property_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.property_id
  , shop_no
  , property_type
  , shop_type
  , status
  , shop_name
  , shop_name_kana
  , shop_short_name
  , zip
  , pref_code
  , address
  , tel
  , fax
  , previous_tenant_name
  , previous_tenant_type
  , previous_tenant_remarks
  , frontal_road_name
  , floor_area
  , rent_tax_excl
  , park_num
  , park_num_remarks
  , therapist_park
  , hope_bed_num
  , initial_bed_num
  , latest_bed_num
  , option_mattress_num
  , booth_form_type
  , pole_signboard_flag
  , shutter_flag
  , auto_door_flag
  , increase_bed
  , latitude
  , longitude
  , registered_user_keyword
  , registered_datetime
  , registered_system
  , registered_module
  , P_02.updated_datetime
  , deleted
  , updated_user_keyword
  , updated_system
  , updated_module
  , version
FROM
  l0_sys_production.property AS P_02
JOIN
  P_01 ON P_01.property_id = P_02.property_id AND P_01.updated_datetime = P_02.updated_datetime
