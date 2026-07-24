-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  pos_sales_id
  , MAX(updated_datetime) AS updated_datetime
FROM
  l0_sys_production.pos_sales
GROUP BY
  pos_sales_id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.updated_datetime, 'JST') AS time
  , P_02.pos_sales_id
  , property_id
  , TD_TIME_FORMAT(TD_TIME_PARSE(business_date, 'JST'), 'yyyy-MM-dd', 'JST') AS business_date
  , shop_no
  , settlement_therapist_id
  , therapist_no
  , cash_sales_tax_incl
  , cash_sales_tax
  , gift_sales_tax_incl
  , gift_sales_tax
  , pay_point_sales_tax_incl
  , pay_point_sales_tax
  , old_gift_sales_tax_incl
  , old_gift_sales_tax
  , paid_point_sales_tax_incl
  , paid_point_sales_tax
  , free_point_sales_tax_incl
  , free_point_sales_tax
  , cash_discount_tax_incl
  , cash_discount_tax
  , point_fee_tax_incl
  , point_fee_tax
  , product_sales_tax_incl
  , product_sales_tax
  , sales_tax_incl
  , sales_tax
  , payment_tax_incl
  , carry_over
  , real_amount
  , shop_reserve
  , shop_comment
  , info_change_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(registered_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS registered_datetime
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.updated_datetime, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS updated_datetime
  , deleted
FROM
  l0_sys_production.pos_sales AS P_02
JOIN
  P_01 ON P_01.pos_sales_id = P_02.pos_sales_id AND P_01.updated_datetime = P_02.updated_datetime
