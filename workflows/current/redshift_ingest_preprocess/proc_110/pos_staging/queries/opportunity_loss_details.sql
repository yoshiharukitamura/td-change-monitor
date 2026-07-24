-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_pos_staging.opportunity_loss_details
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , opportunity_loss_id
  , route
  , col_9_oclock
  , col_10_oclock
  , col_11_oclock
  , col_12_oclock
  , col_13_oclock
  , col_14_oclock
  , col_15_oclock
  , col_16_oclock
  , col_17_oclock
  , col_18_oclock
  , col_19_oclock
  , col_20_oclock
  , col_21_oclock
  , col_22_oclock
  , col_23_oclock
  , col_24_oclock
  , col_25_oclock
  , col_26_oclock
  , col_27_oclock
  , col_28_oclock
  , col_29_oclock
  , total_number_of_losses_per_route
  , TD_TIME_FORMAT(TD_TIME_PARSE(created, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS created
  , TD_TIME_FORMAT(TD_TIME_PARSE(P_02.modified, 'JST'), 'yyyy-MM-dd HH:mm:ss', 'JST') AS modified
  , deleted
  , deleted_date
FROM
  l0_pos_staging.opportunity_loss_details AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
