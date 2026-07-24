-- DIGDAG_INSERT_LINE
with entry_time_slot as (
  select
    td_time_string(td_date_trunc('week', time, 'jst'), 'd!', 'jst') as business_week
    , substr('月火水木金土日', day_of_week(date(business_date)), 1) as business_dow
    , business_hour
    , shop_name
    , count(1) as entered_slot
  from
    _integration_datamart.cls_time_slot_detail
    left join (select property_id, shop_no||'_'||shop_name as shop_name from _integration_datamart.mst_shop) using (property_id)
  where
    td_date_trunc('week', time, 'jst') = td_time_parse('${reference_date}', 'jst')
  group by
    1,2,3,4
)
, tmp as (
  select
    application_time_slot_id
    , business_week
    , business_dow
    , business_hour
    , shop_name
    , td123 - coalesce(entered_slot, 0) as td123
    , td123 - coalesce(entered_slot, 0) as td123_fixed
    -- , cast(ceiling(td123 * 1.2) as bigint) as td123_fixed
    , therapist_name
    , tp_rnk_1
    , case
        when tp_rnk_1 <= ( td123 - coalesce(entered_slot, 0) ) then 0
        else 9
      end as result_tmp
  from
    l2_demand_forecast_auto.timeslot_entry_elected_prep
    left join entry_time_slot using (business_week, business_dow, business_hour, shop_name)
  where
    business_week = '${reference_date}'
)
, h_pre as (
  select
    *
    , lag(result_tmp) over (partition by business_week, business_dow, shop_name, therapist_name order by business_hour) as lag_result
    , lag(business_hour) over (partition by business_week, business_dow, shop_name, therapist_name order by business_hour) as lag_hour
    , lead(result_tmp) over (partition by business_week, business_dow, shop_name, therapist_name order by business_hour) as lead_result
    , lead(business_hour) over (partition by business_week, business_dow, shop_name, therapist_name order by business_hour) as lead_hour
  from
    tmp
)
, h as (
  select
    *
    , case
        when cast(business_hour as bigint) - 1 = cast(lag_hour as bigint) and lag_result = 0 and result_tmp = 9 then 1
        when cast(business_hour as bigint) + 1 = cast(lead_hour as bigint) and lead_result = 0 and result_tmp = 9 then 1
        else result_tmp
      end as result_h
  from
    h_pre
)
, v as (
  select
    *
    , row_number() over (partition by business_week, business_dow, business_hour, shop_name order by result_h, tp_rnk_1) as tp_rnk_2
  from
    h
)
, hv as (
  select
    *
    , case
        when result_h = 0 then '当選'
        -- when result_h = 1 and tp_rnk_2 <= td123_fixed then '救済_横'
        when result_h = 1 then '救済_横'
        when result_h = 9 and tp_rnk_2 <= td123_fixed then '救済_縦'
        else '落選'
      end as result_hv
  from
    v
)
, shop_master as (
  select distinct
    property_id as shop_id
    , shop_no
    , shop_name
  from
    _l1_mysql_core.property as property
    LEFT JOIN  (SELECT property_id, shop_brand as shop_brand_class FROM l0_viewtables.view_shop_extend) USING (property_id) 
    LEFT JOIN  (SELECT cast(id as varchar) as pref_code, cast(mst_area_id as varchar) as area_id ,name as prefectures FROM _l1_mysql_pos.mst_prefectures) USING (pref_code)
    LEFT JOIN  (SELECT cast(id as varchar) as area_id, name as area_class FROM _l1_mysql_pos.mst_areas) USING (area_id)
    LEFT JOIN  (SELECT id as property_id ,business_hour_start ,business_hour_end FROM _l1_mysql_pos.mst_shops) USING (property_id)
    LEFT JOIN  (SELECT property_id ,max_by(open_date,updated_datetime) as open_date ,max_by(business_start_time,updated_datetime) as business_start_time ,max_by(business_end_time,updated_datetime) as business_end_time FROM _l0_mysql_core.property_additional_info GROUP BY 1) USING (property_id)
  WHERE 1=1
    and not regexp_like(shop_brand_class,'店舗外') --categorylist=通常,Green,Green+,Woman,店舗外
    and property_type = '01' -- 01を有効化(＝研修センター・テスト店舗を除外)
  --   and status = '02'-- 02=オープン済を有効化
)
, therapist_master as (
  select
    therapist_id
    , therapist_no
    , name as therapist_name
    , case sex_type
        when '01' then '01_男性'
        when '02' then '02_女性'
        else '不明'
      end as therapist_gender
    , date_diff('year', cast(substr(birthday, 1, 10) as date), cast(td_time_string(td_scheduled_time(), 'd!', 'jst') as date)) as therapist_age
    , total_rate as therapist_reward_rate
  from
    _l0_mysql_core.therapist
    inner join (select therapist_id, max(time) as time from _l0_mysql_core.therapist group by therapist_id) using (therapist_id, time)
    left join (
      select
        therapist_id
        , total_rate
      from
        l0_rs_bigquery.navy_final_remuneration_rate_management
        inner join (
            select
              therapist_id
              , max_by(target_quater, td_time_parse(target_quater||'/1', 'jst')) as target_quater
            from
              l0_rs_bigquery.navy_final_remuneration_rate_management
            group by
              therapist_id
          ) using (therapist_id, target_quater)
      ) using (therapist_id)
)


select
  hv.*
  , shop_id
  , therapist_id
from
  hv
  left join shop_master as sm on split(hv.shop_name, '_')[1] = sm.shop_no
  left join therapist_master as tm on split(hv.therapist_name, '_')[1] = tm.therapist_no
;

select
  shop_name
  , count(if(result_hv='当選', 1, null)) as be_elected
  , count(if(result_hv='救済_縦', 1, null)) as relief_v
  , count(if(result_hv='救済_横', 1, null)) as relief_h
  , count(if(result_hv='落選', 1, null)) as rejection
from
  l2_demand_forecast_auto.timeslot_entry_elected_result_hv
group by
  1
order by
  1
