with agg_tp_slot as (
  select
    therapist_id
    , therapist_no
    , substr(business_date, 1, 10) as business_date
    , sum(if(business_date <= '2019-01-01', original_usage_time, use_time_by_daily_slot)) as use_time_by_daily_slot
    , sum(original_usage_time) as original_usage_time
  from l0_viewtables.tbl_fixed_therapist_daily_report
  left join l0_viewtables.view_shop_extend using (property_id)
  where division = 0
        and coalesce(deleted, 0) = 0
        and shop_brand <> ''
  group by 1,2,3
)

, agg_lead as (
  select
    therapist_id
    , therapist_no
    , business_date
    , lead(business_date, 1) over (partition by therapist_id order by business_date) as next_business_date
    , date_diff('day', cast(business_date as date), lead(cast(business_date as date), 1) over (partition by therapist_id order by business_date)) as diff_business_days
  from agg_tp_slot
  where use_time_by_daily_slot > 0
        and original_usage_time > 0
)

, agg_first_business as (
  select
    therapist_id
    , therapist_no
    , min(business_date) as first_business_date
    , min(if(business_date >='2023-01-02', business_date, null)) as first_business_date_y2023
    , min(if(diff_business_days >= 61 and next_business_date >='2023-01-01', next_business_date, null)) as return_date
  from agg_lead
  group by 1,2
)

, tp_class as (
  select
    therapist_id
    , therapist_no
    , first_business_date
    , first_business_date_y2023
    , td_date_trunc('week', td_time_parse(first_business_date, 'jst'), 'jst') as first_business_week
    , if(first_business_date >= '2023-03-01' and cast(therapist_no as int) < 46776, first_business_date, return_date) as return_date
    , case
        when first_business_date_y2023 is null then 'その他'
        when first_business_date >= '2023-03-01' and cast(therapist_no as int) >= 46776 then '新規'
        when first_business_date >= '2023-03-01' and cast(therapist_no as int) < 46776 then '復帰'
        when first_business_date_y2023 is not null then '既存'
        else 'その他'
      end as tp_class
  from agg_first_business
)

, hst_weekly as (
  select
    therapist_id
    , therapist_no
    , first_business_date
    , first_business_date_y2023
    , w.business_week
    , return_date
    , td_time_string(td_date_trunc('week', td_time_parse(return_date, 'jst'), 'jst'), 'd!', 'jst') as return_business_week
    , case
        when td_date_trunc('week', td_time_parse(first_business_date, 'jst'), 'jst') > w.business_week then 'その他'
        when return_date is not null and td_date_trunc('week', td_time_parse(return_date, 'jst'), 'jst') <= w.business_week then '復帰'
        else tp_class
      end as tp_class
    , date_diff('week', from_unixtime(first_business_week), from_unixtime(w.business_week)) + 1 as passes_week
  from tp_class
  cross join unnest(
    sequence(
      td_date_trunc('week', td_time_parse('${td.each.date_from}', 'jst'), 'jst')
      , td_date_trunc('week', td_time_parse('${td.each.date_to}',   'jst'), 'jst')
      , 60*60*24*7)
    ) as w(business_week)
  where w.business_week >= first_business_week
)

select
  business_week as time
  , td_time_string(business_week, 's!', 'jst') as time_fmt
  , 'processing_date' as time_means
  , therapist_id
  , therapist_no
  , first_business_date
  , first_business_date_y2023
  , business_week
  , return_date
  , return_business_week
  , case
      when tp_class = '新規' and passes_week <= 8 then '新規1-8'
      when tp_class = '新規' and passes_week between 9 and 16 then '新規9-16'
      when tp_class = '新規' and passes_week between 17 and 24 then '新規17-24'
      when tp_class = '新規' and passes_week >= 25 then '新規25+'
      else tp_class
    end as tp_flag
from hst_weekly