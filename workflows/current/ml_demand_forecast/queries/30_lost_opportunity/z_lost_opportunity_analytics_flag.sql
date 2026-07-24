with shop_master as (
  select
    t1.id as mst_shop_id
    , t1.no as mst_shop_no
    , t1.name as mst_shop_name
    , t1.pref_id
    , t2.name as pref_name
    , t2.sort_order as pref_sort_order
    , t1.mst_area_id as area_id
    , t3.name as area_name
    , t3.sort_order as area_sort_order
  from
    _l1_mysql_pos.mst_shops as t1
    left join _l1_mysql_pos.mst_prefectures as t2 on t1.pref_id = t2.id
    left join _l1_mysql_pos.mst_areas as t3 on t1.mst_area_id = t3.id
)
select
  t0.*
  , cardinality(arry_mst_shop_no) as split_count
  , t1.mst_shop_no as mst_shop_no_for_split
  , t2.*
from
  l1_datamart_202210.z_lost_opportunity_analytics_raw_by_user as t0
  cross join unnest (
      arry_mst_shop_no
  ) as t1(mst_shop_no)
  left join shop_master as t2 on t1.mst_shop_no = t2.mst_shop_no