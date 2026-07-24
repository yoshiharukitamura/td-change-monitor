-- DIGDAG_INSERT_LINE
with v as (
  select
    application_time_slot_id
    , business_week
    , business_dow
    , business_hour
    , shop_name
    , td123
    , td123 as td123_fixed
    -- , cast(ceiling(td123 * 1.2) as bigint) as td123_fixed
    , therapist_name
    , tp_rnk_1
    , case
        when tp_rnk_1 <= td123 then '当選'
        when tp_rnk_1 <= cast(ceiling(td123 * 1.2) as bigint) then '救済_縦'
        else '落選'
      end as result_v
  from
    l2_demand_forecast_auto.timeslot_entry_elected_prep
  where
    business_week = '${reference_date}'
)
, h as (
  select
    *
    , lag(result_v) over (partition by business_week, business_dow, shop_name, therapist_name order by business_hour) as lag_result
    , lag(business_hour) over (partition by business_week, business_dow, shop_name, therapist_name order by business_hour) as lag_hour
    , lead(result_v) over (partition by business_week, business_dow, shop_name, therapist_name order by business_hour) as lead_result
    , lead(business_hour) over (partition by business_week, business_dow, shop_name, therapist_name order by business_hour) as lead_hour
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
    _l1_mysql_core.therapist
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
  h.*
  , case
      when cast(business_hour as bigint) - 1 = cast(lag_hour as bigint) and lag_result = '当選' and result_v = '落選' then '救済_横'
      when cast(business_hour as bigint) + 1 = cast(lead_hour as bigint) and lead_result = '当選' and result_v = '落選' then '救済_横'
      else result_v
    end as result_vh
  , shop_id
  , therapist_id
from
  h
  left join shop_master as sm on split(h.shop_name, '_')[1] = sm.shop_no
  left join therapist_master as tm on split(h.therapist_name, '_')[1] = tm.therapist_no
;

select
  shop_name
  , count(if(result_vh='当選', 1, null)) as be_elected
  , count(if(result_vh='救済_縦', 1, null)) as relief_v
  , count(if(result_vh='救済_横', 1, null)) as relief_h
  , count(if(result_vh='落選', 1, null)) as rejection
from
  l2_demand_forecast_auto.timeslot_entry_elected_result_vh
group by
  1
order by
  1
