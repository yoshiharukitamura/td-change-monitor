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

, app_session as (
  select
    processing_date
    , customer_id
    , sum(app_session) as app_session
  from (
    select
      td_time_string(td_date_trunc('week', time, 'jst'), 'd!', 'jst') as processing_date
      , user_pseudo_id
      , max(customer_id) as customer_id
      , count(distinct ga_session_id) as app_session
    from _integration_datamart.z_tmp_cls_app_log_104w
    group by 1,2
  )
  group by 1,2
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
      end as f
    , case
        when coalesce(app_session, 0) = 0 then 'S0'
        when coalesce(app_session, 0) between 1 and 3 then 'S1-3'
        when coalesce(app_session, 0) between 4 and 7 then 'S4-7'
        when coalesce(app_session, 0) >= 8 then 'S8-'
      else '不明'
    end as app_session_range
    /* 新規のnext_week、prev_yearが出るように加工 */
    --, coalesce(shop_no_last_order, 0) as shop_no_last_order
    --, coalesce(shop_name_last_order, '判定不可') as shop_name_last_order
    , nullif(count(distinct customer_id), 0) as customer_count
    , nullif(count(distinct if(order_count >= 1, customer_id)), 0) as order_customer_count
    , sum(order_count) as order_count
    , sum(treatment_minuites) / 60.0 as treatment_hours
    , sum(uriage1)/1000 as uriage1
    , coalesce(sum(app_session), 0) as app_session
  from weekly_customer_status
  full join weekly_order using (processing_date, customer_id)
  full join app_session using (processing_date, customer_id)
  group by 1,2,3,4
  order by 1,2,3,4
)

, tmp as (
  select
    year_of_week(date(processing_date)) as yow
    , week_of_year(date(processing_date)) as woy
    , processing_date
    , r_week
    , f
    , app_session_range
    , coalesce(customer_count, 0) as customer_count
    , coalesce(order_customer_count, 0) as order_customer_count
    , coalesce(order_count, 0) as order_count
    , coalesce(treatment_hours, 0) as treatment_hours
    , coalesce(uriage1, 0) as uriage1
    , coalesce(app_session, 0) as app_session
from week_list
left join agg using(processing_date)
where year_of_week(date(processing_date)) >= 2024
)

select
  yow
  , woy
  , processing_date as "営業日の週"
  , r_week as "R/w"
  , f as "F"
  , app_session_range as "アプリセッション数/週"
  , customer_count as "セグメント顧客数"
  , order_customer_count as "施術顧客数"
  , 1.0 * order_customer_count / sum(order_customer_count) over (partition by processing_date, r_week) as "施術顧客数 構成比"
  , 1.0 * customer_count / sum(customer_count) over (partition by processing_date, r_week) as "APPセッション顧客数 構成比"
  , order_count as "施術数"
  , treatment_hours as "施術時間"
  , uriage1 as "売上1(千円)"
  , app_session as "アプリセッション数"
from tmp
order by 1,2,3,4,5