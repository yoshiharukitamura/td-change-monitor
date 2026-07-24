with week_list as (
  select
    distinct
    processing_date
  from
    _integration_datamart.hst_weekly_customer_rf_w12f
  where 
    time >= td_time_parse('2023-10-01', 'jst')
)

, reserve_log_base as (
  select
    t0.week as processing_date
    , t0.reservation_id
    , coalesce(t0.customer_id, t1.customer_id) as customer_id
    , coalesce(t0.phone_no, t1.phone_no) as phone_no
    , coalesce(t0.email, t1.email) as email
  from
    _integration_datamart.z_tmp_cls_reservation as t0
  left join
    (
      select
        distinct
        reservation_id
        , customer_id
        , phone_no
        , email
      from
        _l1_mysql_pos.orders
    ) as t1
    on t0.reservation_id = t1.reservation_id
)

, prep_reserve_log as (
  select
    t0.processing_date
    , t0.reservation_id
    , t0.customer_id

    , case
        when regexp_replace(t0.phone_no, '[^0-9]', '') = '' then null
        when substr(regexp_replace(t0.phone_no, '[^0-9]', ''), 1, 3) = '000' then null
        else regexp_replace(t0.phone_no, '[^0-9]', '')
      end as phone_norm

    , case
        when lower(trim(t0.email)) = '' then null
        else lower(trim(t0.email))
      end as email_norm

    , td_time_string(td_date_trunc('week', td_time_parse(t1.created_app, 'jst'), 'jst'), 'd!', 'jst') as app_created_week
    , td_time_string(td_date_trunc('week', td_time_parse(coalesce(t1.created, t2.created), 'jst'), 'jst'), 'd!', 'jst') as member_created_week

    , case
        when t0.customer_id is null then null
        when t1.created_app is null and substr(coalesce(t1.created, t2.created), 1, 10) >= '2026-06-23' then 'WEB会員'
        else 'APP会員'
      end as member_type
  from
    reserve_log_base as t0
  left join
    _l1_mysql_hp.customers as t1
    on t0.customer_id = t1.dtb_customer_id
  left join
    _l1_mysql_pos.customers as t2
    on t0.customer_id = t2.id
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

, nonmember_first_reserve as (
  select
    provisional_person_id
    , min(processing_date) as nonmember_first_reserve_week
  from
    gid_3
  group by
    1
)

, customer_first_reserve as (
  select
    customer_id
    , min(processing_date) as first_reserve_week
  from
    gid_3
  group by
    1
)

, weekly_reserve as (
  select
    t0.processing_date
    , t0.reservation_id
    , t0.member_type
    , t0.customer_id
    , t1.provisional_person_id
    , t2.first_reserve_week
    , t3.nonmember_first_reserve_week
    , t0.member_created_week
  from
    prep_reserve_log as t0
  left join
    gid_3 as t1
    on t0.reservation_id = t1.reservation_id
    and t0.processing_date = t1.processing_date
  left join
    customer_first_reserve as t2
    on t0.customer_id = t2.customer_id
  left join
    nonmember_first_reserve as t3
    on t1.provisional_person_id = t3.provisional_person_id
)

, weekly_customer_status as (
  select
    distinct
    processing_date
    , customer_id
    , r_week
    , f
    , first_order_unixtime
    , nomination_last_order
    , shop_no_last_order
    , shop_name as shop_name_last_order
  from
    _integration_datamart.hst_weekly_customer_rf_w12f as t0
  left join 
    _integration_datamart.mst_shop as t1
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

  select
    t0.time
    , td_time_string(td_date_trunc('week', t0.time, 'jst'), 'd!', 'jst') as processing_date
    , coalesce(t0.customer_id, t1.customer_id) as customer_id
    , t1.provisional_person_id
    , coalesce(cast(coalesce(t0.customer_id, t1.customer_id) as varchar), t1.provisional_person_id) as person_key
    , t1.first_reserve_week
    , t1.nonmember_first_reserve_week
    , t0.order_id
    , t1.member_type
    , t1.member_created_week
    , case
        when coalesce(t0.customer_id, t1.customer_id) is not null then '会員'
        when coalesce(t0.customer_id, t1.customer_id) is null and t1.provisional_person_id is not null and t1.processing_date = t1.nonmember_first_reserve_week then '非会員_新規'
        when coalesce(t0.customer_id, t1.customer_id) is null and t1.provisional_person_id is not null and t1.processing_date > t1.nonmember_first_reserve_week then '非会員_既存'
        else '非会員_不明'
      end as guest_flag
    , max(case
        when t1.nonmember_first_reserve_week < t1.first_reserve_week then 1
        else 0
      end) as nonmember_history_flag
    , max(case
        when t1.first_reserve_week >= t1.member_created_week then 1
        else 0
      end) as member_reserve_first_flag
    , max(if(regexp_like(t0.product_name, '[+&]'), 1, 0)) as set_flag
    , max(if(regexp_like(t0.product_name, 'ヘッド|ハンド|整体|ケア|足裏|集中'), 1, 0)) as addon_flag
    , max(if(regexp_like(t0.product_name, 'ヘッド|ハンド|整体|足つぼ|ケア|足裏|集中'), 1, 0)) as standard_flag
    , count(distinct t0.order_id) as order_count
    , sum(if(t0.order_id_hour_seq = 1, t0.treatment_minutes, 0)) as treatment_minutes
    , max(if(t0.nomination_fee > 0.0, 1, 0)) as nomination_flag
    , max(if(t0.nomination_fee > 0.0 and t0.nomination_fee < 182.0, 1, 0)) as nomination_gender_flag
    , max(if(t0.nomination_fee >= 182.0, 1, 0)) as nomination_tp_flag
    , max(if(t0.product_type_id = 4, 1, 0)) as op_flag
    , max(if(t0.product_name in ('マットレス', 'Cool プレミアムマットレス') and t0.product_type_id = 4, 1, 0)) as op_pmat_flag
    , max(if(t0.product_name not in ('マットレス', 'Cool プレミアムマットレス') and t0.product_type_id = 4, 1, 0)) as op_other_flag
    , count(distinct if(regexp_like(t0.product_name, 'ほぐし|ヘッド|ハンド|足つぼ|整体|ケア|足裏|集中'), t0.product_name)) as menu_count
    , max(if(regexp_like(t0.product_name, '足つぼ'), 1, 0)) as foot_flag
  from
    prep_order_log as t0
  left join
    weekly_reserve as t1
    on t0.reservation_id = t1.reservation_id
  group by
    1,2,3,4,5,6,7,8,9,10,11