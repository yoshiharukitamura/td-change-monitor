with shop_master as (
  select distinct
    property_id as shop_id
    , shop_no
    , shop_name
    , pref_code
    , prefectures
    , area_id
    , area_class
  from
    _l1_mysql_core.property as property
    LEFT JOIN  (SELECT property_id, shop_brand as shop_brand_class FROM l0_viewtables.view_shop_extend) USING (property_id) 
    LEFT JOIN  (SELECT cast(id as varchar) as pref_code, cast(mst_area_id as varchar) as area_id ,name as prefectures FROM _l1_mysql_pos.mst_prefectures) USING (pref_code)
    LEFT JOIN  (SELECT cast(id as varchar) as area_id, name as area_class FROM _l1_mysql_pos.mst_areas) USING (area_id)
    LEFT JOIN  (SELECT id as property_id ,business_hour_start ,business_hour_end FROM _l1_mysql_pos.mst_shops) USING (property_id)
    LEFT JOIN  (SELECT property_id ,max_by(open_date,updated_datetime) as open_date ,max_by(business_start_time,updated_datetime) as business_start_time ,max_by(business_end_time,updated_datetime) as business_end_time FROM _l1_mysql_core.property_additional_info GROUP BY 1) USING (property_id)
  WHERE 1=1
    and not regexp_like(shop_brand_class,'店舗外') --categorylist=通常,Green,Green+,Woman,店舗外
    and property_type = '01' -- 01を有効化(＝研修センター・テスト店舗を除外)
)
, log_order as (
  select
    shop_no||'_'||shop_name as shop_name
    , td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , business_dow
    , business_hour
    , sum(treatment_minutes) as treatment_minutes
  from
    l1_datamart_202210.prep_orders
    inner join shop_master using (shop_no)
  group by
    1,2,3,4
)
, log_timeslot as (
  select
    shop_no||'_'||shop_name as shop_name
    , td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , business_dow
    , business_hour
    , sum(time_slot) as timeslot_result
  from
    l2_shop_db_dev.prep_time_slot
    inner join shop_master using (shop_no)
  where
    is_confirmed = 1
  group by
    1,2,3,4
)
, log_forecast_20230904 as (
  select
    mst_shop_id
    , td_time_add(business_day, cast(business_hour as varchar)||'h', 'jst') as treatment_time
    , mst_shop_no||'_'||mst_shop_name as shop_name
    , pref_code
    , prefectures
    , area_id
    , area_class
    , forecast_week as business_week
    , business_dow
    , business_hour
    , time_slot as timeslot_td
    , td1
    , td2
    , td3
    , forecast_value
    , loss_opps_fin_value
  from
    l2_demand_forecast_auto.fin_timeslot_raw_vtable as t1
    inner join shop_master as t2 on t1.mst_shop_no = t2.shop_no
  where
    weeks_ahead_riraku = 0
    and forecast_week >= '2023-09-04'
)

select
  *
from
  log_forecast_20230904
  left join log_order using (shop_name, business_week, business_dow, business_hour)
  left join log_timeslot using (shop_name, business_week, business_dow, business_hour)
where
  td_time_parse(business_week, 'jst') < td_date_trunc('week', td_scheduled_time(), 'jst')
