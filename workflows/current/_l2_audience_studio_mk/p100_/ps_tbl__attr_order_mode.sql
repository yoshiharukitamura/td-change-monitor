with customer_list as (
  select
    customer_id
  from
    _integration_datamart.cls_order_detail
  group by
    1
)

, prep_order_log as (
  select
    customer_id
    , order_id
    , case
        when nomination_fee > 100.0 then therapist_id
        else null
      end as nominated_therapist_id
    , case day_of_week(date(business_date))
        when 1 then '月曜日'
        when 2 then '火曜日'
        when 3 then '水曜日'
        when 4 then '木曜日'
        when 5 then '金曜日'
        when 6 then '土曜日'
        when 7 then '日曜日'
      end as business_dow
    , property_id
    , min(business_hour) as business_hour
  from
    _integration_datamart.cls_order_detail
  group by
    1,2,3,4,5
)

, agg_order_shop as (
  select
    customer_id
    , shop_name
    , order_shop_count
    , row_number() over (partition by customer_id order by order_shop_count desc) as order_shop_rn
  from (
    select
      customer_id
      , shop_name
      , count(distinct order_id) as order_shop_count
    from
      prep_order_log
    left join
      (select property_id, shop_name from _integration_datamart.mst_shop) using (property_id)
    group by
      1,2
  )
)

, agg_nominated_therapist as (
  select
    customer_id
    , nominated_therapist_id
    , nominated_therapist_count
    , row_number() over (partition by customer_id order by nominated_therapist_count desc) as nominated_therapist_rn
  from (
    select
      customer_id
      , nominated_therapist_id
      , count(distinct order_id) as nominated_therapist_count
    from
      prep_order_log
    group by
      1,2
  )
)

, agg_order_dow as (
  select
    customer_id
    , business_dow
    , dow_order_count
    , row_number() over (partition by customer_id order by dow_order_count desc) as dow_order_rn
  from (
    select
      customer_id
      , business_dow
      , count(distinct order_id) as dow_order_count
    from
      prep_order_log
    group by
      1,2
  )
)

, agg_business_hour as (
  select
    customer_id
    , business_hour
    , start_hour_count
    , row_number() over (partition by customer_id order by start_hour_count desc) as start_hour_rn
  from (
    select
      customer_id
      , business_hour
      , count(distinct order_id) as start_hour_count
    from
      prep_order_log
    group by
      1,2
  )
)

, agg_order_menu as (
  select
    customer_id
    , product_name
    , menu_order_count
    , row_number() over (partition by customer_id order by menu_order_count desc) as menu_order_rn
  from (
    select
      customer_id
      , product_name
      , count(distinct order_id) as menu_order_count
    from
      _integration_datamart.cls_order_detail
    where
      product_name is not null
    group by
      1,2
  )
)

select
  customer_id as mstr__id
  , business_dow as most_order_dow
  , business_hour as most_order_timeslot
  , product_name as most_order_menu
  , shop_name as most_order_shop
  , nominated_therapist_id as most_nomination_tp
from
  customer_list
left join 
  (select customer_id, business_dow from agg_order_dow where dow_order_rn = 1) using (customer_id)
left join
  (select customer_id, business_hour from agg_business_hour where start_hour_rn = 1) using (customer_id)
left join
  (select customer_id, product_name from agg_order_menu where menu_order_rn = 1) using (customer_id)
left join
  (select customer_id, nominated_therapist_id from agg_nominated_therapist where nominated_therapist_rn = 1) using (customer_id)
left join
  (select customer_id, shop_name from agg_order_shop where order_shop_rn = 1) using (customer_id)