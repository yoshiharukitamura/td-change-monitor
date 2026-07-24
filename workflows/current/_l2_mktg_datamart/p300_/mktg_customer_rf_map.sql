with customer_rf as (
  select
    week
    -- , if(r_week <= 52, lpad(cast(r_week as varchar), 2, '0'), '53+') as r
    -- , if(f <= 12, lpad(cast(f as varchar), 2, '0'), '13+') as f
    , if(r_week <= 52, r_week, 53) as r
    , if(f <= 12, f, 13) as f
    , customer_id
    , sales_amount
    , treatment_minutes
    , shop_no_last_order
  from _integration_datamart.hst_weekly_customer_rf
  where td_time_range(time, td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-12w'), td_date_trunc('day', td_scheduled_time(), 'jst'), 'jst')
)

select
  week
  , r
  , f
  , count(distinct customer_id) as customer_cnt
  , sum(sales_amount)/1000 as uriage1_kjpy
  , sum(treatment_minutes)/60 as treatment_hours
from customer_rf
group by 1,2,3
order by 1,2,3