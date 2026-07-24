
SELECT
  ${moment(session_date).unix()} AS time
  , id
  , mst_shop_id
  , category_id
FROM
  l0_pos_staging.shop_categories
GROUP BY
  id
  , mst_shop_id
  , category_id
