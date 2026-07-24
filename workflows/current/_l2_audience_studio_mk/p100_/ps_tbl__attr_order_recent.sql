with last_app_login as (
  select
    dtb_customer_id as customer_id
    , max(td_time_parse(last_login_app, 'jst')) as last_app_login_date_datetime
  from
    _l1_mysql_hp.customers
  where
    coalesce(deleted, 0) = 0
  group by
    1
)

, last_reservation as (
  select
    customer_id
    , max(created_unixtime) as last_reserve_datetime
  from
    _integration_datamart.z_tmp_cls_reservation
  group by
    1
)

, prep_last_order as (
  select
    customer_id
    , order_id
    , business_date
    , property_id
    , min(business_hour) as business_hour
  from
    _integration_datamart.cls_order_detail
  inner join
    (select customer_id, max_by(order_id, business_date) as order_id
     from _integration_datamart.cls_order_detail 
     group by 1) using (customer_id, order_id)
  group by
    1,2,3,4
)

, last_order as (
  select
    customer_id
    , td_time_parse(business_date, 'jst') as last_order_datetime
    , case day_of_week(date(business_date))
        when 1 then '月曜日'
        when 2 then '火曜日'
        when 3 then '水曜日'
        when 4 then '木曜日'
        when 5 then '金曜日'
        when 6 then '土曜日'
        when 7 then '日曜日'
      end as last_order_dow
    , business_hour as last_order_timeslot
    , shop_name as last_order_shop
    , area_name as last_order_shop_area
    , pref_name as last_order_shop_pref
    , case
        when rate = 1 then '満足'
        when rate = 2 then '不満足'
        else null
      end as last_order_review
  from
    prep_last_order
  left join
    (select property_id, shop_name, area_name, pref_name from _integration_datamart.mst_shop) using (property_id)
  left join
    (select distinct id as order_id, rate from _l1_mysql_hp.reviews) using (order_id)
)

, prep_weekly_customer_status as (
  select
    distinct
    processing_date
    , customer_id
    , r_week
    , f
    , first_order_unixtime
  from
    _integration_datamart.hst_weekly_customer_rf_w12f
  where
    time >= td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-7d', 'jst')
    and time <= td_date_trunc('week', td_scheduled_time(), 'jst')
)

, prep_weekly_order as (
  select
    td_time_string(td_date_trunc('week', time, 'jst'), 'd!', 'jst') as processing_date
    , customer_id
    , coalesce('c'||cast(customer_id as varchar), 'o'||cast(order_id as varchar)) as order_customer_id
  from
    _integration_datamart.cls_order_detail
  where
    time >= td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-14d', 'jst')
)

, prep_customer_rf as (
  select
    customer_id
    , processing_date
    , case
        when r_week is null and customer_id is null then '01_非会員'
        when r_week is null and customer_id is not null then '02_新規（当週）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) between 1 and 12 then '03_新規（オンボーディング）'

        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f = 1 then '04_既存_ライト（12wF1）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f = 2 then '05_既存_ミドル（12wF2）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f >= 3 then '06_既存_ヘビー（12wF3+）'
        when r_week between 13 and 52 and f = 0 then '07_疎遠（R/w13-52）'
        when r_week >= 53 and f = 0 then '08_離反（R/w53+）'
      end as r_segment
    , r_week
    , f
  from prep_weekly_customer_status
  full join prep_weekly_order using (processing_date, customer_id)
)

, prep_prev_prep_customer_rf as (
  select
    td_time_string(td_time_add(td_time_parse(processing_date, 'jst'), '7d', 'jst'), 'd!', 'jst') as processing_date
    , customer_id
    , r_segment
    , r_week
    , f
  from
    prep_customer_rf
)

, last_customer_rf as (
  select
    t0.customer_id
    , t0.r_segment
    , t0.r_week
    , t0.f as w12_f
    , coalesce(t1.r_segment,
               case when t0.customer_id is not null then '01_非会員'
                    else '01_非会員' end) as prev_r_segment
    , t1.r_week as prev_r_week
    , t1.f as prev_w12_f
  from prep_customer_rf as t0
  left join prep_prev_prep_customer_rf as t1
    on t0.processing_date = t1.processing_date
   and t0.customer_id = t1.customer_id
)

select
  coalesce(t0.customer_id, t1.customer_id, t2.customer_id, t3.customer_id) as mstr__id
  , last_app_login_date_datetime
  , last_reserve_datetime
  , last_order_datetime
  , last_order_dow
  , last_order_timeslot
  , last_order_shop
  , last_order_shop_area
  , last_order_shop_pref
  , last_order_review
  , r_segment
  , r_week
  , w12_f
  , prev_r_segment
  , prev_r_week
  , prev_w12_f
from
  last_app_login as t0
full outer join
  last_reservation as t1
  on t0.customer_id = t1.customer_id
full outer join
  last_order as t2
  on coalesce(t0.customer_id, t1.customer_id) = t2.customer_id
full outer join
  last_customer_rf as t3
  on coalesce(t0.customer_id, t1.customer_id, t2.customer_id) = t3.customer_id
where
  coalesce(t0.customer_id, t1.customer_id, t2.customer_id, t3.customer_id) is not null