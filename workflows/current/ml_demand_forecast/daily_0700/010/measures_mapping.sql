with shop_master as (
  select distinct
    property_id as mst_shop_id
    , case when status = '01' then '01:オープン前' 
        when status = '02' then '02:オープン済'
        when status = '03' then '03:閉店済'
        when status = '04' then '04:申込'
        when status = '05' then '05:交渉中'
        when status = '06' then '06:解約申請済'      
        when status = '07' then '07:閉店済（オープン前）' else '' end as shop_status_class
    ,'りらくる' as shop_type
  from
    _l0_mysql_core.property as property
    INNER JOIN (SELECT property_id ,max(updated_datetime) as updated_datetime FROM _l0_mysql_core.property GROUP BY 1) USING (property_id,updated_datetime)
    LEFT JOIN  (SELECT property_id, shop_brand as shop_brand_class FROM l0_viewtables.view_shop_extend) USING (property_id) 
    LEFT JOIN  (SELECT cast(id as varchar) as pref_code, cast(mst_area_id as varchar) as area_id ,name as prefectures FROM _l0_mysql_pos.mst_prefectures) USING (pref_code)
    LEFT JOIN  (SELECT cast(id as varchar) as area_id, name as area_class FROM _l0_mysql_pos.mst_areas) USING (area_id)
    LEFT JOIN  (SELECT id as property_id ,business_hour_start ,business_hour_end FROM l1_unique_for_smc.mst_shops_unique) USING (property_id)
    LEFT JOIN  (SELECT property_id ,max_by(open_date,updated_datetime) as open_date ,max_by(business_start_time,updated_datetime) as business_start_time ,max_by(business_end_time,updated_datetime) as business_end_time FROM _l0_mysql_core.property_additional_info GROUP BY 1) USING (property_id)
  WHERE 1=1
    and not regexp_like(shop_brand_class,'店舗外') --categorylist=通常,Green,Green+,Woman,店舗外
    and property_type = '01' -- 01を有効化(＝研修センター・テスト店舗を除外)
  --   and status = '02'-- 02=オープン済を有効化
)
, reference_time_slot as (
  select
    mst_shop_id
    , business_dow
    , business_hour
    , td1 as ref_td1
    , td2 as ref_td2
    , td3 as ref_td3
    , td1+td2 as ref_td12
    , td1+td2+td3 as ref_td123
    , '${td.each.reference_week}' as reference_week
  from
    l2_demand_forecast_auto.fin_timeslot_raw_vtable
  where
    -- 最小値は 2023-06-12
    forecast_week = '${td.each.reference_week}'
    and weeks_ahead_riraku = 0
)
, master_time_slot as (
  select
    mst_shop_id
    , mst_shop_no as shop_no
    , mst_shop_name as shop_name
    , forecast_week as business_week
    , business_day
    , business_dow
    , business_hour
    , case
        when td1 - ref_td1 > 0 then '増加'
        when td1 - ref_td1 = 0 then '同じ'
        when td1 - ref_td1 < 0 then '減少'
      end as td1_change
    , case
        when td1+td2 - ref_td12 > 0 then '増加'
        when td1+td2 - ref_td12 = 0 then '同じ'
        when td1+td2 - ref_td12 < 0 then '減少'
      end as td12_change
    , td1
    , td2
    , td3
    , td1+td2 as td12
    , td1+td2+td3 as td123
    , ref_td1
    , ref_td2
    , ref_td3
    , ref_td12
    , ref_td123
    , reference_week
  from
    l2_demand_forecast_auto.fin_timeslot_raw_vtable
    left join reference_time_slot using (mst_shop_id, business_dow, business_hour)
  where
    weeks_ahead_riraku = 0
)
, quest_time_slot as (
  select
    shop_id as mst_shop_id
    , business_week as reference_week
    , business_date as business_day
    , substr('月火水木金土日', dow(cast(business_date as date)), 1) as business_dow
    , business_hour
    , sum(time_slot) as time_slot__quest
  from
    l2_shop_db_dev.time_slot_progress_prep
  where
    flag = '02_quest'
  group by
    1,2,3,4,5
)
, confirmed_time_slot as (
  select
    shop_id as mst_shop_id
    , business_week as reference_week
    , business_date as business_day
    , substr('月火水木金土日', dow(cast(business_date as date)), 1) as business_dow
    , business_hour
    , sum(time_slot) as time_slot__confirmed
  from
    l2_shop_db_dev.time_slot_progress_prep
  where
    flag = '05_confirmed'
  group by
    1,2,3,4,5
)
, quest_stop_shop_list as (
  select
    substr(business_week, 1, 10) as business_week
    , property_id as mst_shop_id
    , max_by(type, time) as quest_stop_type
  from
    l2_demand_forecast_auto.spreadsheets_quest_stop_list_shop
  group by
    1,2
)

select
    mst_shop_id
    , shop_no
    , shop_name
    , shop_status_class
    , shop_type
    , business_week
    , business_day
    , business_dow
    , business_hour
    , td1_change
    , td12_change
    , td1
    , td2
    , td3
    , td12
    , td123
    , ref_td1
    , ref_td2
    , ref_td3
    , ref_td12
    , ref_td123
    , coalesce(time_slot__quest, 0) as time_slot__quest
    , coalesce(time_slot__confirmed, 0) as time_slot__confirmed
    , reference_week
    , coalesce(ref_time_slot__quest, 0) as ref_time_slot__quest
    , coalesce(ref_time_slot__confirmed, 0) as ref_time_slot__confirmed
    , quest_stop_type
    , if(business_week>='2023-08-07', '色分け', null) as color_coding
from
  master_time_slot
  left join quest_stop_shop_list using (business_week, mst_shop_id)
  inner join shop_master using (mst_shop_id)
  left join (
      select mst_shop_id, business_day, business_hour, time_slot__quest
      from quest_time_slot
   ) using (mst_shop_id, business_day, business_hour)
  left join (
      select mst_shop_id, business_day, business_hour, time_slot__confirmed
      from confirmed_time_slot
   ) using (mst_shop_id, business_day, business_hour)
  left join (
      select mst_shop_id, reference_week, business_dow, business_hour, time_slot__quest as ref_time_slot__quest
      from quest_time_slot
   ) using (mst_shop_id, reference_week, business_dow, business_hour)
  left join (
      select mst_shop_id, reference_week, business_dow, business_hour, time_slot__confirmed as ref_time_slot__confirmed
      from confirmed_time_slot
   ) using (mst_shop_id, reference_week, business_dow, business_hour)
where
  reference_week is not null
  and td_time_parse(business_week, 'jst') <= td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-7d', 'jst')
