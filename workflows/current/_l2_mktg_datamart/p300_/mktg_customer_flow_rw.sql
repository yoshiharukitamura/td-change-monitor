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
    , sum(treatment_minutes) as treatment_minuites
    , sum(uriage1) as uriage1
  from
    cls_order_detail
  where
    time >= td_time_parse('2023-10-01', 'jst')
    and order_id_hour_seq = 1
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
        when r_week is null and customer_id is null then '01_非会員(新規)'
        when r_week is null and customer_id is not null then '02_来店なし会員(新規)'
        when r_week between 1 and 4 then '03_R/w1-4'
        when r_week between 5 and 8 then '04_R/w5-8'
        when r_week between 9 and 12 then '05_R/w9-12'
        when r_week between 13 and 24 then '06_R/w13-24'
        when r_week between 25 and 52 then '07_R/w24-52'
        when r_week >= 53 then '08_R/w53-'
      else '不明'
    end as r_week
    /* 新規のnext_week、prev_yearが出るように加工 */
    , coalesce(shop_no_last_order, 0) as shop_no_last_order
    , coalesce(shop_name_last_order, '判定不可') as shop_name_last_order
    , nullif(count(distinct customer_id), 0) as customer_count
    , nullif(count(distinct if(order_count >= 1, customer_id)), 0) as order_customer_count
    , sum(order_count) as order_count
    , sum(treatment_minuites) / 60.0 as treatment_hours
    , sum(uriage1)/1000 as uriage1
  from weekly_customer_status
  full join weekly_order using (processing_date, customer_id)
  group by 1,2,3,4
)

, merged as (
  select
    year_of_week(date(processing_date)) as yow
    , week_of_year(date(processing_date)) as woy
    , processing_date
    , r_week
    , shop_no_last_order
    , shop_name_last_order
    , if(r_week = '02_来店なし会員(新規)', coalesce(not_order_customer_count, 0), coalesce(customer_count, 0)) as customer_count
    , coalesce(order_customer_count, 0) as order_customer_count
    , coalesce(order_count, 0) as order_count
    , coalesce(treatment_hours, 0) as treatment_hours
    , coalesce(uriage1, 0) as uriage1
  from week_list
  left join agg using(processing_date)
  left join app_not_order_customer using(processing_date)
)

, prev_year as (
  select
    yow + 1 as yow
    , woy
    , r_week
    , shop_no_last_order
    , shop_name_last_order
    , customer_count as prev_y_customer_count
    , order_customer_count as prev_y_order_customer_count
    , uriage1 as prev_y_uriage1
    , sum(customer_count) over (partition by r_week, shop_no_last_order order by processing_date rows between 3 preceding and current row) / 4 as prev_y_avg_customer_count_last4w
    , sum(order_customer_count) over (partition by r_week, shop_no_last_order order by processing_date rows between 3 preceding and current row) / 4 as prev_y_avg_order_customer_count_last4w
  from merged
)

, next_week as (
  select
    /* 年跨ぎ用に日付ベースでずらす*/
    year_of_week(date(td_time_string(td_time_add(td_date_trunc('week', td_time_parse(processing_date, 'jst'), 'jst'), '-7d', 'jst'), 'd!','jst'))) as yow
    , week_of_year(date(td_time_string(td_time_add(td_date_trunc('week', td_time_parse(processing_date, 'jst'), 'jst'), '-7d', 'jst'), 'd!','jst'))) as woy
    , r_week
    , shop_no_last_order
    , shop_name_last_order
    , customer_count as next_w_customer_count
    , order_customer_count as next_w_order_customer_count
  from merged
)

, current_year as (
  select
    yow
    , woy
    , processing_date
    , r_week
    , shop_no_last_order
    , shop_name_last_order
    , customer_count
    , sum(customer_count) over (partition by r_week, shop_no_last_order order by processing_date rows between 3 preceding and current row) / 4 as avg_customer_count_last4w
    , order_customer_count
    , sum(order_customer_count) over (partition by r_week, shop_no_last_order order by processing_date rows between 3 preceding and current row) / 4 as avg_order_customer_count_last4w
    , order_count
    , treatment_hours
    , uriage1
  from merged
)

select
  yow
  , woy
  , 'w'||replace(processing_date, '-','') as business_week
  , r_week
  , shop_no_last_order
  , shop_name_last_order
  , customer_count
  , order_customer_count
  , avg_customer_count_last4w as forecast_customer_count
  , avg_order_customer_count_last4w as forecast_order_customer_count
  , order_count
  , treatment_hours
  , uriage1
  , prev_y_avg_customer_count_last4w as prev_y_customer_count
  , prev_y_avg_order_customer_count_last4w as prev_y_order_customer_count
  , next_w_customer_count
  , next_w_order_customer_count
from current_year
left join prev_year using (yow, woy, r_week, shop_no_last_order, shop_name_last_order)
left join next_week using (yow, woy, r_week, shop_no_last_order, shop_name_last_order)
where yow >= 2024