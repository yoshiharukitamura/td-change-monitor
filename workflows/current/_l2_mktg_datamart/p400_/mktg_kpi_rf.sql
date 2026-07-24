with week_list as (
  select
    distinct
    processing_date
  from
    hst_weekly_customer_rf
  where 
    time >= td_time_parse('2023-10-01', 'jst')
)

, weekly_customer_status as (
  select
    distinct
    processing_date
    , customer_id
    , r_week
    , f
    , nomination_last_order
    , shop_no_last_order
    , shop_name as shop_name_last_order
  from
    hst_weekly_customer_rf as t0
  left join 
    mst_shop as t1
    on cast(t0.shop_no_last_order as varchar) = t1.shop_no
  where
    t0.time between td_time_parse('2023-10-01', 'jst') and td_date_trunc('week', td_scheduled_time(), 'jst')
)

, weekly_order as (
  select
    td_time_string(td_date_trunc('week', time, 'jst'), 'd!', 'jst') as processing_date
    , customer_id
    , coalesce('c'||cast(customer_id as varchar), 'o'||cast(order_id as varchar)) as order_customer_id
    , count(distinct order_id) as order_count
    , sum(if(order_id_hour_seq = 1, treatment_minutes, 0)) as treatment_minutes
    , max(if(nomination_fee > 0.0, 1, 0)) as nomination_flag
    , max(if(product_type_id = 4, 1, 0)) as option_flag
  from
    cls_order_detail
  where
    time >= td_time_parse('2023-10-01', 'jst')
  group by
    1,2,3
)

, app_not_order_customer as (
  select
    td_time_string(week, 'd!', 'jst') as processing_date,
    count(if(first_res_week is null or first_res_week > week, 1)) as not_order_customer_count
  from (
    select
      week
      , user_pseudo_id
      , min(if(customer_id is not null, week)) over (partition by user_pseudo_id) as first_res_week
    from (
      select
        td_date_trunc('week', time, 'jst') as week,
        user_pseudo_id,
        max(customer_id) as customer_id
      from _integration_datamart.z_tmp_cls_app_log_104w
      group by 1,2
    )
  )
  group by 1
)

, agg as (
  select
    processing_date
    , case
        when r_week is null and customer_id is null then '01_新規(非会員)'
        when r_week is null and customer_id is not null then '02_新規(会員)'
        when r_week between 1 and 4 then '03_R/w1-4'
        when r_week between 5 and 8 then '04_R/w5-8'
        when r_week between 9 and 12 then '05_R/w9-12'
        when r_week between 13 and 24 then '06_R/w13-24'
        when r_week between 25 and 52 then '07_R/w24-52'
        when r_week >= 53 then '08_R/w53-'
        else '不明'
      end as r_week
    , case
        when f between 1 and 5 then 'F1-5'
        when f >= 6 then 'F6-'
        else '-'
      end as f
    /* 新規のnext_week、prev_yearが出るように加工 */
    --, coalesce(shop_no_last_order, 0) as shop_no_last_order
    --, coalesce(shop_name_last_order, '判定不可') as shop_name_last_order
    , nullif(count(distinct customer_id), 0) as customer_count
    , nullif(count(distinct if(order_count >= 1, customer_id)), 0) as order_customer_count
    , sum(order_count) as order_count
    , sum(treatment_minutes) as treatment_minutes
    , sum(if(nomination_flag = 1, order_count, 0)) as nomination_order_count
    , sum(if(option_flag = 1, order_count, 0)) as option_order_count
  from weekly_customer_status
  full join weekly_order using (processing_date, customer_id)
  group by 1,2,3
)

select
  year_of_week(date(processing_date)) as yow
  , week_of_year(date(processing_date)) as woy
  , processing_date
  , r_week
  , f
  --, shop_no_last_order
  --, shop_name_last_order
  , if(r_week = '02_新規(会員)', coalesce(not_order_customer_count, 0), coalesce(customer_count, 0)) as customer_uu
  , coalesce(order_customer_count, 0) as order_customer_uu
  , 1.0 * coalesce(order_customer_count, 0) / sum(coalesce(order_customer_count, 0)) over (partition by processing_date, r_week) as order_customer_uu_rate
  , coalesce(order_count, 0) as order_count
  , coalesce(treatment_minutes, 0) as treatment_minutes
  , coalesce(option_order_count, 0) as option_order_count
  , coalesce(nomination_order_count, 0) as nomination_order_count
from week_list
left join agg using(processing_date)
left join app_not_order_customer using(processing_date)
where year_of_week(date(processing_date)) >= 2024
order by
  1,2,3,4,5