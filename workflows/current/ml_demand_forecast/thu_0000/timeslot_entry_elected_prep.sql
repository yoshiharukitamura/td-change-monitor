with entry as (
  select
    application_time_slot_id
    , business_week
    , business_dow
    , business_hour
    , shop_name
    , therapist_name
    , tp_rnk_1
  from
    l2_demand_forecast_auto.timeslot_entry_elected_raw
  where
    data_type = '01_希望枠(個人)'
    and business_week = '${reference_date}'
)
, timeslot as (
  select
    business_week
    , business_dow
    , business_hour
    , shop_name
    , if(
        case
            when is_manual_fixed = 0 and td_time_parse(business_day, 'jst') between td_time_parse(date_from, 'jst') and td_time_parse(date_to, 'jst')
              then
                case
                  when regexp_like(business_dow_fixed, '土日祝')
                    then cast(ceiling(time_slot * if(business_hour between weekend_peak_from and weekend_peak_to, weekend_peak_num, weekend_base_num)) as bigint)
                  else
                    cast(ceiling(time_slot * if(business_hour between weekdays_peak_from and weekdays_peak_to, weekdays_peak_num, weekdays_base_num)) as bigint)
                end
            else time_slot
          end > latest_bed_num
        , latest_bed_num
        , case
            when is_manual_fixed = 0 and td_time_parse(business_day, 'jst') between td_time_parse(date_from, 'jst') and td_time_parse(date_to, 'jst')
              then
                case
                  when regexp_like(business_dow_fixed, '土日祝')
                    then cast(ceiling(time_slot * if(business_hour between weekend_peak_from and weekend_peak_to, weekend_peak_num, weekend_base_num)) as bigint)
                  else
                    cast(ceiling(time_slot * if(business_hour between weekdays_peak_from and weekdays_peak_to, weekdays_peak_num, weekdays_base_num)) as bigint)
                end
            else time_slot
          end
        ) as td123
    , weeks_ago
  from
    l2_demand_forecast_auto.timeslot_entry_elected_raw as t1
    left join (
        select property_id, date_from, date_to
                , weekend_peak_from, weekend_peak_to, weekend_peak_num, weekend_base_num
                , weekdays_peak_from, weekdays_peak_to, weekdays_peak_num, weekdays_base_num
        from l2_demand_forecast_auto.spreadsheets_timeslot_multiply_v3
        where time = td_time_add(td_scheduled_time(), '-13h')
      ) as t2 on t1.mst_shop_id = t2.property_id
          and td_time_parse(t1.business_day, 'jst') between td_time_parse(t2.date_from, 'jst') and td_time_parse(t2.date_to, 'jst')
  where
    data_type = '時間枠_RRK補正'
    and business_week = '${reference_date}'
    and weeks_ago = 5
)

select
  application_time_slot_id
  , business_week
  , business_dow
  , business_hour
  , shop_name
  , td123
  , therapist_name
  , tp_rnk_1
from
  entry
  left join timeslot using (business_week, business_dow, business_hour, shop_name)
