drop table if exists l2_shop_db_dev.analytics_20231215;
create table l2_shop_db_dev.analytics_20231215 as
with target_shops as (
  select distinct
    shop_no as mst_shop_no
  from (
      select shop_no from l2_demand_forecast_auto.prep_spreadsheet_entry_preference_survey_20240101
      union all select shop_no from l2_demand_forecast_auto.prep_spreadsheet_entry_preference_survey_20240108
      union all select shop_no from l2_demand_forecast_auto.prep_spreadsheet_entry_preference_survey_prd where business_date >= '2023-01-15'
  )
)
select
  '必要枠_RRK補正' as data_type
  , forecast_week as business_week
  , weeks_ahead_riraku as weeks_ago
  , mst_shop_no||'_'||mst_shop_name as shop_name
  , business_dow
  , business_hour
  , time_slot
  , td1
  , td1+td2 as td12
  , td1+td2+td3 as td123
from
  l2_demand_forecast_auto.fin_timeslot_raw_vtable_fixed
  inner join target_shops using (mst_shop_no)
where
  forecast_week >= '2024-01-01'
;


insert into l2_shop_db_dev.analytics_20231215
select
  '事前E_当落選' as data_type
  , business_week
  , shop_name
  , therapist_name
  , business_dow
  , business_hour
  , 1 as time_slot
  , result_vh as elected_result
from
  l2_demand_forecast_auto.timeslot_entry_elected_result_vh
where
  business_week < '2024-01-15'
;


insert into l2_shop_db_dev.analytics_20231215
select
  '事前E_当落選' as data_type
  , business_week
  , shop_name
  , therapist_name
  , business_dow
  , business_hour
  , 1 as time_slot
  , result_hv as elected_result
from
  l2_demand_forecast_auto.timeslot_entry_elected_result_hv
where
  business_week >= '2024-01-15'
;


insert into l2_shop_db_dev.analytics_20231215
with therapist_master as (
  select therapist_id, therapist_no, name as therapist_name
  from _l0_mysql_core.therapist
    inner join (select therapist_id, max(time) as time from _l0_mysql_core.therapist group by therapist_id) using (therapist_id, time)
)
, shop_master as (
  select property_id as shop_id, shop_no, shop_name
  from _l0_mysql_core.property
    inner join (select property_id, max(time) as time from _l0_mysql_core.property group by property_id) using (property_id, time)
)
select
  '受注枠_確定' as data_type
  , business_week
  , 0 as weeks_ago
  , shop_no||'_'||shop_name as shop_name
  , therapist_no||'_'||therapist_name as therapist_name
  , substr('月火水木金土日', dow(cast(business_date as date)), 1) as business_dow
  , business_hour
  , time_slot
from
  l2_shop_db_dev.time_slot_progress_prep
  inner join therapist_master using (therapist_id)
  inner join shop_master using (shop_id)
where
  flag = '05_confirmed'
  and business_week >= '2024-01-01'
  and shop_no||'_'||shop_name in (select distinct shop_name from l2_shop_db_dev.analytics_20231215)
;


insert into l2_shop_db_dev.analytics_20231215
with therapist_master as (
  select therapist_id, therapist_no, name as therapist_name
  from _l0_mysql_core.therapist
    inner join (select therapist_id, max(time) as time from _l0_mysql_core.therapist group by therapist_id) using (therapist_id, time)
)
, shop_master as (
  select property_id as shop_id, shop_no, shop_name
  from _l0_mysql_core.property
    inner join (select property_id, max(time) as time from _l0_mysql_core.property group by property_id) using (property_id, time)
)
, tp_rank as (
  select therapist_id, processing_week, therapist_rank_class as tp_rank_class
  from therapist_rank_class_weekly
)

select
  '受注枠_進捗' as data_type
  , business_week
  , offset_diff as weeks_ago
  , shop_no||'_'||shop_name as shop_name
  , therapist_no||'_'||therapist_name as therapist_name
  , tp_rank_class
  , substr('月火水木金土日', dow(cast(business_date as date)), 1) as business_dow
  , business_hour
  , time_slot
from
  l2_shop_db_dev.time_slot_progress_prep
  inner join therapist_master using (therapist_id)
  inner join shop_master using (shop_id)
  left join tp_rank using (therapist_id, processing_week)
where
  flag = '01_week_offset'
  and business_week >= '2024-01-01'
  and shop_no||'_'||shop_name in (select distinct shop_name from l2_shop_db_dev.analytics_20231215)
;


insert into l2_shop_db_dev.analytics_20231215
select distinct
  '_必要枠数' as data_type
  , business_week
  , weeks_ago
  , shop_name
  , business_dow
  , business_hour
from
  l2_shop_db_dev.analytics_20231215
;


insert into l2_shop_db_dev.analytics_20231215
select distinct
  '_希望枠数' as data_type
  , business_week
  , shop_name
  , therapist_name
  , business_dow
  , business_hour
from
  l2_shop_db_dev.analytics_20231215
where
  therapist_name is not null
;


insert into l2_shop_db_dev.analytics_20231215
select distinct
  '_履行枠数' as data_type
  , business_week
  , shop_name
  , therapist_name
  , business_dow
  , business_hour
from
  l2_shop_db_dev.analytics_20231215
where
  therapist_name is not null
;


insert into l2_shop_db_dev.analytics_20231215
select distinct
  '_受注枠数' as data_type
  , business_week
  , shop_name
  , therapist_name
  , business_dow
  , business_hour
  , t2.is_pre_entry
from
  l2_shop_db_dev.analytics_20231215
  left join (
      select business_week, shop_name, therapist_name, max(time_slot) as is_pre_entry
      from l2_shop_db_dev.analytics_20231215
      where data_type = '事前E_当落選'
      group by 1,2,3
    ) as t2 using (business_week, shop_name, therapist_name)
where
  therapist_name is not null
;

