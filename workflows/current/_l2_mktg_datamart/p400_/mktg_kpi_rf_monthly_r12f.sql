with month_list as (
  select
    distinct
    processing_date
  from
    hst_monthly_customer_rf_w12f
)

, prep_reserve_log as (
  select
    td_time_string(td_date_trunc('month', created_unixtime, 'jst'), 'd!', 'jst') as processing_date
    , t0.reservation_id
    , t0.customer_id
    , case
        when regexp_replace(coalesce(t0.phone_no, t1.phone_no), '[^0-9]', '') = '' then null
        when substr(regexp_replace(coalesce(t0.phone_no, t1.phone_no), '[^0-9]', ''), 1, 3) = '000' then null
        else regexp_replace(coalesce(t0.phone_no, t1.phone_no), '[^0-9]', '')
      end as phone_norm
    , case
        when lower(trim(coalesce(t0.email, t1.email))) = '' then null
        else lower(trim(coalesce(t0.email, t1.email)))
      end as email_norm
  from
    _integration_datamart.z_tmp_cls_reservation as t0
  left join
    (select distinct reservation_id, phone_no, email from _l1_mysql_pos.orders) as t1
    on t0.reservation_id = t1.reservation_id
)

, prep_provisional_id as (
  select processing_date, reservation_id, customer_id, concat('p:', phone_norm) as id_key 
  from prep_reserve_log where phone_norm is not null
  union all
  select processing_date, reservation_id, customer_id, concat('e:', email_norm) as id_key 
  from prep_reserve_log where email_norm is not null
)

, gid_0 as (
  select
    processing_date
    , reservation_id
    , customer_id
    , min(id_key) as provisional_person_id
  from
    prep_provisional_id
  group by
    1,2,3
)

, provisional_id_1 as (
  select
    t0.id_key
    , min(t1.provisional_person_id) as provisional_person_id
  from
    prep_provisional_id as t0
  inner join
    gid_0 as t1
    on t0.reservation_id = t1.reservation_id
  group by
    1
)

, gid_1 as (
  select
    t0.processing_date
    , t0.reservation_id
    , t0.customer_id
    , min(t1.provisional_person_id) as provisional_person_id
  from
    prep_provisional_id as t0
  inner join
    provisional_id_1 as t1
    on t0.id_key = t1.id_key
  group by
    1,2,3
)

, provisional_id_2 as (
  select
    t0.id_key
    , min(t1.provisional_person_id) as provisional_person_id
  from
    prep_provisional_id as t0
  inner join
    gid_1 as t1
    on t0.reservation_id = t1.reservation_id
  group by
    1
)

, gid_2 as (
  select
    t0.processing_date
    , t0.reservation_id
    , t0.customer_id
    , min(t1.provisional_person_id) as provisional_person_id
  from
    prep_provisional_id as t0
  inner join
    provisional_id_2 as t1
    on t0.id_key = t1.id_key
  group by
    1,2,3
)

, provisional_id_3 as (
  select
    t0.id_key
    , min(t1.provisional_person_id) as provisional_person_id
  from
    prep_provisional_id as t0
  inner join
    gid_2 as t1
    on t0.reservation_id = t1.reservation_id
  group by
    1
)

, gid_3 as (
  select
    t0.processing_date
    , t0.reservation_id
    , t0.customer_id
    , min(t1.provisional_person_id) as provisional_person_id
  from
    prep_provisional_id as t0
  inner join
    provisional_id_3 as t1
    on t0.id_key = t1.id_key
  group by
    1,2,3
)

, provisional_id as (
  select
    provisional_person_id
    , min(processing_date) as first_reserve_month
  from
    gid_3
  group by
    1
)

, monthly_reserve as (
  select
    t0.processing_date
    , t0.reservation_id
    , t1.provisional_person_id
    , t2.first_reserve_month
    , case
        when t0.customer_id is not null then '会員'
        when t0.customer_id is null and t1.provisional_person_id is not null and t0.processing_date = t2.first_reserve_month then '非会員_新規'
        when t0.customer_id is null and t1.provisional_person_id is not null and t0.processing_date > t2.first_reserve_month then '非会員_既存'
        else '非会員_不明'
      end as guest_flag
  from
    prep_reserve_log as t0
  left join
   gid_3 as t1
    on t0.reservation_id = t1.reservation_id
  left join
    provisional_id as t2
    on t1.provisional_person_id = t2.provisional_person_id
)

, monthly_customer_status as (
  select
    distinct
    processing_date
    , customer_id
    , cast(customer_id as varchar) as person_key
    , r_week
    , f
    , first_order_unixtime
    , nomination_last_order
    , shop_no_last_order
    , shop_name as shop_name_last_order
  from
    hst_monthly_customer_rf_w12f as t0
  left join 
    mst_shop as t1
    on cast(t0.shop_no_last_order as varchar) = t1.shop_no
  where
    t0.time between td_time_parse('2023-10-01', 'jst') and td_date_trunc('week', td_scheduled_time(), 'jst')
)

, prep_order_log as (
  select
    time
    , customer_id
    , order_id
    , order_id_hour_seq
    , nomination_fee
    , treatment_minutes
    , reservation_id
    , case
        when regexp_like(product_name, 'プレミアム|集中') then 1
        else product_type_id
      end as product_type_id
    , product_name
  from
    _integration_datamart.cls_order_detail
  where
    time >= td_time_parse('2023-10-01', 'jst')
)

, monthly_order as (
  select
    td_time_string(td_date_trunc('month', time, 'jst'), 'd!', 'jst') as processing_date
    , customer_id
    , provisional_person_id
    , coalesce(cast(customer_id as varchar), provisional_person_id) as person_key
    , first_reserve_month
    , order_id
    , case
        when customer_id is not null and reservation_id is null then '会員'
        when customer_id is null and reservation_id is null and guest_flag is null then '非会員_不明'
        else guest_flag
      end as guest_flag
    , max(if(regexp_like(product_name, '[+&]'), 1, 0)) as set_flag
    , max(if(regexp_like(product_name, 'ヘッド|ハンド|整体|ケア|足裏|集中'), 1, 0)) as addon_flag
    , max(if(regexp_like(product_name, 'ヘッド|ハンド|整体|足つぼ|ケア|足裏|集中'), 1, 0)) as standard_flag
    , count(distinct order_id) as order_count
    , sum(if(order_id_hour_seq = 1, treatment_minutes, 0)) as treatment_minutes
    , max(if(nomination_fee > 0.0, 1, 0)) as nomination_flag
    , max(if(nomination_fee > 0.0 and nomination_fee < 182.0, 1, 0)) as nomination_gender_flag
    , max(if(nomination_fee >= 182.0, 1, 0)) as nomination_tp_flag
    , max(if(product_type_id = 4, 1, 0)) as op_flag
    , max(if(product_name in ('マットレス', 'Cool プレミアムマットレス') and product_type_id = 4, 1, 0)) as op_pmat_flag
    , max(if(product_name not in ('マットレス', 'Cool プレミアムマットレス') and product_type_id = 4, 1, 0)) as op_other_flag
    , count(distinct if(regexp_like(product_name, 'ほぐし|ヘッド|ハンド|足つぼ|整体|ケア|足裏|集中'), product_name)) as menu_count
    , max(if(regexp_like(product_name, '足つぼ'), 1, 0)) as foot_flag
  from
    prep_order_log
  left join
    monthly_reserve using (reservation_id)
  group by
    1,2,3,4,5,6,7
)

, app_not_order_customer as (
  select
    td_time_string(month, 'd!', 'jst') as processing_date,
    count(if(first_res_month is null or first_res_month > month, 1)) as not_order_customer_count
  from (
    select
      month
      , user_pseudo_id
      , min(if(customer_id is not null, month)) over (partition by user_pseudo_id) as first_res_month
    from (
      select
        td_date_trunc('month', time, 'jst') as month,
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
        when guest_flag = '非会員_新規' then '01_非会員（新規）'
        when guest_flag = '非会員_既存' and first_reserve_month is not null 
          and date_diff('week', date(first_reserve_month), date(processing_date)) between 0 and 12 then '02_非会員_新規（オンボーディング）'
        when guest_flag = '非会員_既存' then '03_非会員（既存）'
        when customer_id is null or guest_flag = '非会員_不明' then '04_非会員（不明）'
        when r_week is null and customer_id is not null then '05_新規（当週）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) between 0 and 12 then '06_新規（オンボーディング）'

        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f = 1 then '07_既存_ライト（12wF1）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f = 2 then '08_既存_ミドル（12wF2）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f >= 3 then '09_既存_ヘビー（12wF3+）'
        when r_week between 13 and 52 and f = 0 then '10_疎遠（R/w13-52）'
        when r_week >= 53 and f = 0 then '11_離反（R/w53+）'
      end as segment
    /* 新規のnext_week、prev_yearが出るように加工 */
    --, coalesce(shop_no_last_order, 0) as shop_no_last_order
    --, coalesce(shop_name_last_order, '判定不可') as shop_name_last_order
    , nullif(count(distinct coalesce(cast(customer_id as varchar), person_key)), 0) as customer_count
    , nullif(count(distinct if(order_count >= 1, coalesce(cast(customer_id as varchar), person_key))), 0) as order_customer_count
    , sum(order_count) as order_count
    , sum(treatment_minutes) as treatment_minutes
    , sum(if(nomination_flag = 1, order_count, 0)) as nomination_order_count
    , sum(if(nomination_flag = 1 and nomination_tp_flag = 1, order_count, 0)) as nomination_tp_order_count
    , sum(if(nomination_flag = 1 and nomination_gender_flag = 1, order_count, 0)) as nomination_gender_order_count

    , sum(if(standard_flag = 1, order_count, 0)) as set_order_count
    , sum(if(foot_flag = 1, order_count, 0)) as set_foot_order_count
    , sum(if(addon_flag = 1, order_count, 0)) as set_other_order_count

    , sum(if(op_flag = 1, order_count, 0)) as option_order_count
    , sum(if(op_pmat_flag = 1, order_count, 0)) as option_pmatt_order_count
    , sum(if(op_other_flag = 1, order_count, 0)) as option_other_order_count
  from monthly_customer_status
  full join monthly_order using (processing_date, customer_id, person_key)
  group by 1,2
)

select
  substr(processing_date, 1, 4) as yom
  , substr(processing_date, 6, 2) as moy
  , processing_date
  , segment
  --, shop_no_last_order
  --, shop_name_last_order
  , if(segment = '05_新規（当週）', coalesce(not_order_customer_count, 0), coalesce(customer_count, 0)) as customer_uu
  , coalesce(order_customer_count, 0) as order_customer_uu
  , 1.0 * coalesce(order_customer_count, 0) / sum(coalesce(order_customer_count, 0)) over (partition by processing_date) as order_customer_uu_rate
  , coalesce(order_count, 0) as order_count
  , coalesce(treatment_minutes, 0) as treatment_minutes
  , coalesce(nomination_order_count, 0) as nomination_order_count
  , coalesce(nomination_tp_order_count, 0) as nomination_tp_order_count
  , coalesce(nomination_gender_order_count, 0) as nomination_gender_order_count
  , coalesce(set_order_count, 0) as set_order_count
  , coalesce(set_foot_order_count, 0) as set_foot_order_count
  , coalesce(set_other_order_count, 0) as set_other_order_count
  , coalesce(option_order_count, 0) as option_order_count
  , coalesce(option_pmatt_order_count, 0) as option_pmatt_order_count
  , coalesce(option_other_order_count, 0) as option_other_order_count
from month_list
left join agg using(processing_date)
left join app_not_order_customer using(processing_date)
where year_of_week(date(processing_date)) >= 2024
order by
  1,2,3,4