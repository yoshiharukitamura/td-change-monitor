-- DIGDAG_INSERT_LINE
with target_shops as (
  select distinct
    shop_no as mst_shop_no
  from 
    ${source_table}
)
/*
-- 時間枠_TD予測
select
  '時間枠_TD予測' as data_type
  , forecast_week as business_week
  , weeks_ahead_riraku as weeks_ago
  , mst_shop_no||'_'||mst_shop_name as shop_name
  , cast(null as varchar) as therapist_name
  , business_dow
  , business_hour
  , time_slot
  , td1
  , td1+td2 as td12
  , td1+td2+td3 as td123
  , forecast_value/60 as z_forecast_hour
  , loss_opps_fin_value/60 as z_loss_opps_hour
  , cast(null as double) as treatment_minutes
from
  _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
  inner join target_shops using (mst_shop_no)
where
  forecast_week >= '2023-07-17'
  and business_hour between 9 and 23
union all
select
  '時間枠_TD予測' as data_type
  , forecast_week as business_week
  , weeks_ahead_riraku as weeks_ago
  , mst_shop_no||'_'||mst_shop_name as shop_name
  , cast(null as varchar) as therapist_name
  , business_dow
  , 24 as business_hour
  , time_slot
  , td1
  , td1+td2 as td12
  , td1+td2+td3 as td123
  , forecast_value/60 as z_forecast_hour
  , loss_opps_fin_value/60 as z_loss_opps_hour
  , cast(null as double) as treatment_minutes
from
  _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
  inner join target_shops using (mst_shop_no)
where
  forecast_week >= '2023-07-17'
  and business_hour = 23
union all
select
  '時間枠_TD予測' as data_type
  , forecast_week as business_week
  , weeks_ahead_riraku as weeks_ago
  , mst_shop_no||'_'||mst_shop_name as shop_name
  , cast(null as varchar) as therapist_name
  , business_dow
  , 25 as business_hour
  , time_slot
  , td1
  , td1+td2 as td12
  , td1+td2+td3 as td123
  , forecast_value/60 as z_forecast_hour
  , loss_opps_fin_value/60 as z_loss_opps_hour
  , cast(null as double) as treatment_minutes
from
  _l2_demand_forecast_gcp.fin_timeslot_raw_vtable
  inner join target_shops using (mst_shop_no)
where
  forecast_week >= '2023-07-17'
  and business_hour = 23

union all
*/

-- 時間枠_RRK補正
select
  '時間枠_RRK補正' as data_type
  , forecast_week as business_week
  , weeks_ahead_riraku as weeks_ago
  , mst_shop_no||'_'||mst_shop_name as shop_name
  , latest_bed_num
  , cast(null as varchar) as therapist_name
  , business_dow
  , business_hour
  , time_slot
  , td1
  , td1+td2 as td12
  , td1+td2+td3 as td123
  , forecast_value/60 as z_forecast_hour
  , loss_opps_fin_value/60 as z_loss_opps_hour
  , cast(null as double) as treatment_minutes
  , mst_shop_id, business_day, business_dow_fixed, is_manual_fixed /* timeslot_multiply紐付け用 */
from
  l2_demand_forecast_auto.fin_timeslot_raw_vtable_fixed
  inner join target_shops using (mst_shop_no)
where
  forecast_week >= '2023-07-17'
  and business_hour between 9 and 23
union all
select
  '時間枠_RRK補正' as data_type
  , forecast_week as business_week
  , weeks_ahead_riraku as weeks_ago
  , mst_shop_no||'_'||mst_shop_name as shop_name
  , latest_bed_num
  , cast(null as varchar) as therapist_name
  , business_dow
  , 24 as business_hour
  , time_slot
  , td1
  , td1+td2 as td12
  , td1+td2+td3 as td123
  , forecast_value/60 as z_forecast_hour
  , loss_opps_fin_value/60 as z_loss_opps_hour
  , cast(null as double) as treatment_minutes
  , mst_shop_id, business_day, business_dow_fixed, is_manual_fixed /* timeslot_multiply紐付け用 */
from
  l2_demand_forecast_auto.fin_timeslot_raw_vtable_fixed
  inner join target_shops using (mst_shop_no)
where
  forecast_week >= '2023-07-17'
  and business_hour = 23
union all
select
  '時間枠_RRK補正' as data_type
  , forecast_week as business_week
  , weeks_ahead_riraku as weeks_ago
  , mst_shop_no||'_'||mst_shop_name as shop_name
  , latest_bed_num
  , cast(null as varchar) as therapist_name
  , business_dow
  , 25 as business_hour
  , time_slot
  , td1
  , td1+td2 as td12
  , td1+td2+td3 as td123
  , forecast_value/60 as z_forecast_hour
  , loss_opps_fin_value/60 as z_loss_opps_hour
  , cast(null as double) as treatment_minutes
  , mst_shop_id, business_day, business_dow_fixed, is_manual_fixed /* timeslot_multiply紐付け用 */
from
  l2_demand_forecast_auto.fin_timeslot_raw_vtable_fixed
  inner join target_shops using (mst_shop_no)
where
  forecast_week >= '2023-07-17'
  and business_hour = 23
;

-- 希望枠データ
insert into l2_demand_forecast_auto.timeslot_entry_elected_raw
with therapist_priority as (
  select
    therapist_id
    , reference_quarter
    , total_rate as final_remuneration
  from
    l0_rs_bigquery.navy_final_remuneration_rate_management
    inner join (
        select
          therapist_id
          , max_by(target_quater, td_time_parse(target_quater||'/1', 'jst')) as target_quater
          , td_time_string(max(td_time_parse(target_quater||'/1', 'jst')), 'd!','jst') as reference_quarter
        from
          l0_rs_bigquery.navy_final_remuneration_rate_management
        group by
          therapist_id
      ) using (therapist_id, target_quater)
)
, hist_treatment_minutes as (
  select
    therapist_no
    , sum(treatment_minutes_in_hour) as achievement_treatment_minutes
  from
    _integration_datamart.cls_order_detail
    left join _integration_datamart.mst_therapist
    using (therapist_id)
  group by
    therapist_no
)
select
  '01_希望枠(個人)' as data_type
  , td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst') as business_week
  , application_time_slot_id
  , cast(null as bigint) as weeks_ago
  , shop_no||'_'||shop_name as shop_name
  , latest_bed_num
  , t1.therapist_no||'_'||therapist_name as therapist_name
  , business_dow
  , business_hour
  , 1 as time_slot
  , cast(null as bigint) as td1
  , cast(null as bigint) as td12
  , cast(null as bigint) as td123
  , cast(null as double) as z_forecast_hour
  , cast(null as double) as z_loss_opps_hour
  , cast(null as double) as treatment_minutes
  , final_remuneration
  , achievement_treatment_minutes
  , row_number() over (
        partition by td_time_string(td_date_trunc('week', td_time_parse(business_date, 'jst'), 'jst'), 'd!', 'jst'), shop_no, business_dow, business_hour
        order by final_remuneration desc, coalesce(achievement_treatment_minutes, 0) desc
      ) as tp_rnk_1
from
  ${source_table} as t1
  left join therapist_priority as t2 on t1.therapist_id = t2.therapist_id
  left join hist_treatment_minutes as t3 on t1.therapist_no = t3.therapist_no
;

