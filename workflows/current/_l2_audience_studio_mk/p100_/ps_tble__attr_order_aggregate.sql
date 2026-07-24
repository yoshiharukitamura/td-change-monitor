with agg_reservation as (
  select
    customer_id
    , count(distinct reservation_id) as reservation_count
    , count(distinct if(reserved_from = 'APP', reservation_id)) as reservation_app_count
  from
    _integration_datamart.z_tmp_cls_reservation
  where
    status > 0
  group by
    customer_id 
)

, prep_order_log as (
  select
    customer_id
    , order_id
    , case day_of_week(date(t0.business_date))
        when 1 then '月'
        when 2 then '火'
        when 3 then '水'
        when 4 then '木'
        when 5 then '金'
        when 6 then '土'
        when 7 then '日'
      end as business_dow
    , case
        when holiday_type_name in ('日本の祝日', 'りらくの祝日') then '祝日'
      else '平日or休日'
      end as business_date_type
    , min(business_hour) as business_hour
    , case
        when nomination_fee = 0.0 then '指名なし'
        when nomination_fee > 0.0 and nomination_fee < 100.0 then '性別指名'
        when nomination_fee > 100.0 then 'TP指名'
        else null
      end as nomination_type
    , therapist_id
    , max(if(treatment_minutes >= 90, 1, 0)) as over90_flag
    , max(if(regexp_like(product_name, '足つぼ'), 1, 0)) as foot_flag
    , max(if(product_type_id = 4, 1, 0)) as option_flag
    , max(if(rate in (1,2), 1, 0)) as review_flag
    , max(if(rate = 1, 1, 0)) as review_positive_flag
    , max(if(rate = 2, 1, 0)) as review_negative_flag
  from
    _integration_datamart.cls_order_detail as t0
  left join
    (select distinct business_date, holiday_type_name from _integration_datamart.mst_datetime) as t1
    on t0.business_date = t1.business_date
  left join
    (select distinct id, rate from _l1_mysql_hp.reviews) as t2 
    on t0.order_id = t2.id
  group by
    1,2,3,4,6,7
)

, agg_order as (
  select
    customer_id
    , count(distinct order_id) as order_count
    , count(distinct if(business_dow = '月' and business_date_type = '平日or休日', order_id)) as order_count_mon
    , count(distinct if(business_dow = '火' and business_date_type = '平日or休日', order_id)) as order_count_tue
    , count(distinct if(business_dow = '水' and business_date_type = '平日or休日', order_id)) as order_count_wed
    , count(distinct if(business_dow = '木' and business_date_type = '平日or休日', order_id)) as order_count_thu
    , count(distinct if(business_dow = '金' and business_date_type = '平日or休日', order_id)) as order_count_fri
    , count(distinct if(business_dow = '土' and business_date_type = '平日or休日', order_id)) as order_count_sat
    , count(distinct if(business_dow = '日' and business_date_type = '平日or休日', order_id)) as order_count_sun
    , count(distinct if(business_date_type = '祝日', order_id)) as order_count_holi

    , count(distinct if(business_hour between 6 and 9, order_id)) as order_count_ts_6_9
    , count(distinct if(business_hour between 10 and 12, order_id)) as order_count_ts_10_12
    , count(distinct if(business_hour between 13 and 15, order_id)) as order_count_ts_13_15
    , count(distinct if(business_hour between 16 and 18, order_id)) as order_count_ts_16_18
    , count(distinct if(business_hour between 19 and 21, order_id)) as order_count_ts_19_21
    , count(distinct if(business_hour between 22 and 24, order_id)) as order_count_ts_22_24
    , count(distinct if(business_hour between 25 and 29, order_id)) as order_count_ts_25_29

    , count(distinct if(nomination_type = 'TP指名', order_id)) as tp_nomination_count
    , count(distinct if(nomination_type = 'TP指名', therapist_id)) as tp_nomination_uu
    , count(distinct if(nomination_type = '性別指名', order_id)) as gender_nomination_count

    , count(distinct if(over90_flag = 1, order_id)) as treatment_90min_count
    , count(distinct if(foot_flag = 1, order_id)) as treatment_foot_count
    , count(distinct if(option_flag = 1, order_id)) as option_count
    
    , count(distinct if(review_flag = 1, order_id)) as review_count
    , count(distinct if(review_flag = 1 and review_positive_flag = 1, order_id)) as review_positive_count
    , count(distinct if(review_flag = 1 and review_negative_flag = 1, order_id)) as review_negative_count
  from
    prep_order_log
  group by
    1
)

, agg_giftcard as (
  select
    customer_id
    , count(distinct id) as gift_card_count
  from
    _l1_mysql_pos.gift_cards
  where
    coalesce(deleted, 0) = 0
  group by
    1
)

, point_log as (
  select
    customer_id
    , t0.id as point_id
    , type
    , reason
    , t1.amount
  from
    _l1_mysql_point.cashable_points as t0
  left join
    _l1_mysql_point.cashable_point_details as t1
    on t0.id = t1.cashable_point_id
)

, agg_point as (
  select
    customer_id
    , sum(if(type = 'BONUS_POINT', amount, 0)) as bonus_point_count
    , sum(if(type = 'LIMITED_TIME_BONUS_POINT', amount, 0)) as limited_bonus_point_count
    , sum(if(type = 'CHARGE_POINT', amount, 0)) as charge_point_count
    , count(distinct if(type = 'CHARGE_POINT' and amount > 0, point_id)) as charge_point_charge_count
    , count(distinct if(type = 'BONUS_POINT' and reason not in ('OPERATED_BY_ADMIN', 'EXPIRED') and amount < 0, point_id)) as bonus_point_use_count
    , count(distinct if(type = 'LIMITED_TIME_BONUS_POINT' and reason not in ('OPERATED_BY_ADMIN', 'EXPIRED') and amount < 0, point_id)) as limited_bonus_point_use_count
    , count(distinct if(type = 'CHARGE_POINT' and reason not in ('OPERATED_BY_ADMIN', 'EXPIRED') and amount < 0, point_id)) as charge_point_use_count
  from
    point_log
  group by
    1
)

select
  customer_id as mstr__id
  , coalesce(reservation_count, 0) as reservation_count
  , coalesce(reservation_app_count, 0) as reservation_app_count

  , order_count
  , order_count_mon
  , order_count_tue
  , order_count_wed
  , order_count_thu
  , order_count_fri
  , order_count_sat
  , order_count_sun
  , order_count_holi

  , order_count_ts_6_9
  , order_count_ts_10_12
  , order_count_ts_13_15
  , order_count_ts_16_18
  , order_count_ts_19_21
  , order_count_ts_22_24
  , order_count_ts_25_29

  , tp_nomination_count
  , tp_nomination_uu
  , gender_nomination_count

  , treatment_90min_count
  , treatment_foot_count
  , option_count
    
  , review_count
  , review_positive_count
  , review_negative_count

  , coalesce(gift_card_count, 0) as gift_card_count

  , coalesce(bonus_point_count, 0) as bonus_point_count
  , coalesce(limited_bonus_point_count, 0) as limited_bonus_point_count
  , coalesce(charge_point_count, 0) as charge_point_count
  , coalesce(charge_point_charge_count, 0) as charge_point_charge_count
  , coalesce(bonus_point_use_count, 0) as bonus_point_use_count
  , coalesce(limited_bonus_point_use_count, 0) as limited_bonus_point_use_count
  , coalesce(charge_point_use_count, 0) as charge_point_use_count
from
  agg_order
left join
  agg_reservation using (customer_id)
left join
  agg_giftcard using (customer_id)
left join
  agg_point using (customer_id)