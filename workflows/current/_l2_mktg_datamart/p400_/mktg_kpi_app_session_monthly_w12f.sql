with customer_rf_shop as (
  select distinct
    time
    , customer_id
    , first_order_unixtime
    , r_week
    , f
  from
    _integration_datamart.hst_monthly_customer_rf_w12f
)
, app_session_master as (
  select
    user_pseudo_id
    , ga_session_id
    , td_time_string(month, 'd!', 'jst') as month
    , customer_id
    , shop_no
    , traffic_source_medium
  from (
      select distinct user_pseudo_id, ga_session_id, td_date_trunc('month', event_unixtime, 'jst') as month
      from _integration_datamart.z_tmp_cls_app_log_104w
    )
    left join (
        select user_pseudo_id, td_date_trunc('month', event_unixtime, 'jst') as month, max_by(customer_id, event_unixtime) as customer_id
        from _integration_datamart.z_tmp_cls_app_log_104w
        where customer_id is not null
        group by 1,2
      ) using (user_pseudo_id, month)
    left join (
        select user_pseudo_id, td_date_trunc('month', event_unixtime, 'jst') as month, max_by(shop_no, event_unixtime) as shop_no
        from _integration_datamart.z_tmp_cls_app_log_104w
        where shop_no is not null
        group by 1,2
      ) using (user_pseudo_id, month)
    left join (
        select user_pseudo_id, td_date_trunc('month', event_unixtime, 'jst') as month, min_by(traffic_source_medium, event_unixtime) as traffic_source_medium
        from _integration_datamart.z_tmp_cls_app_log_104w
        group by 1,2
      ) using (user_pseudo_id, month)
)
, sys_reservation as (
  select reservation_id, customer_id
  from _integration_datamart.z_tmp_cls_reservation
  where reserved_from = 'APP' and parent_reservation_id is null
)

, id_map_by_reservation as (
  select
    user_pseudo_id
    , month
    , customer_id
    , min(month) over (partition by user_pseudo_id order by month) as first_reserve_month
  from (
    select
      user_pseudo_id
      , td_time_string(td_date_trunc('month', event_unixtime, 'jst'), 'd!','jst') as month
      , max_by(customer_id, event_unixtime) as customer_id
    from
      _integration_datamart.z_tmp_cls_app_reserve
      inner join sys_reservation using (reservation_id)
    group by
      1,2
  )
)

, tmp as (
  select
    substr(td_time_string(td_date_trunc('month', t0.event_unixtime, 'jst'), 'd!', 'jst'), 1, 4) as yom
    , substr(td_time_string(td_date_trunc('month', t0.event_unixtime, 'jst'), 'd!', 'jst'), 6, 2) as moy
    , case
        when coalesce(t2.customer_id, t3.customer_id) is null and t3.month = t3.first_reserve_month then '01_非会員（新規）'
        when coalesce(t2.customer_id, t3.customer_id) is null 
          and date_diff('week', date(t3.first_reserve_month), date(t3.month)) between 1 and 12 then '02_非会員_新規（オンボーディング）'
        when coalesce(t2.customer_id, t3.customer_id) is null 
          and date_diff('week', date(t3.first_reserve_month), date(t3.month)) >= 13 then '03_非会員（既存）'
        when coalesce(t2.customer_id, t3.customer_id) is null then '04_非会員（不明）'
        when td_time_parse(t2.month, 'jst') <= td_date_trunc('month', coalesce(t4.first_order_unixtime, td_scheduled_time()), 'jst') then '05_新規（当週）'
        when date_diff('week', date(td_time_string(td_date_trunc('month', t4.first_order_unixtime, 'jst'), 'd!', 'jst')), date(t2.month)) between 1 and 12 then '06_新規（オンボーディング）'
        
        when date_diff('week', date(td_time_string(td_date_trunc('month', t4.first_order_unixtime, 'jst'), 'd!', 'jst')), date(t2.month)) >= 13 and
          r_week between 1 and 12 and f = 1 then '07_既存_ライト（12wF1）'
        when date_diff('week', date(td_time_string(td_date_trunc('month', t4.first_order_unixtime, 'jst'), 'd!', 'jst')), date(t2.month)) >= 13 and
          r_week between 1 and 12 and f = 2 then '08_既存_ミドル（12wF2）'
        when date_diff('week', date(td_time_string(td_date_trunc('month', t4.first_order_unixtime, 'jst'), 'd!', 'jst')), date(t2.month)) >= 13 and
          r_week between 1 and 12 and f >= 3 then '09_既存_ヘビー（12wF3+）'
        when r_week between 13 and 52 and f = 0 then '10_疎遠（R/w13-52）'
        when r_week >= 53 and f = 0 then '11_離反（R/w53+）'
      end as segment
    -- , coalesce(t2.shop_no, t4.shop_no_last_order) as "ShopNo"
    , count(distinct t0.user_pseudo_id||t0.ga_session_id) as app_session
    , count(distinct if(t0.event_status in (1,2,3,4), t0.user_pseudo_id, null)) as app_session_uu
    --, count(distinct if(t0.event_status in (2,3,4), t0.user_pseudo_id, null)) as "予約行動UU数"
    --, count(distinct if(t0.event_status in (3,4), t0.user_pseudo_id, null)) as "予約確認UU数"
    , count(distinct if(t0.event_status in (4), t0.user_pseudo_id, null)) as reservation_complete_uu
    --, count(distinct if(t0.event_status in (4), t1.reservation_id, null)) as "予約施術数"
    -- , td_time_string(td_date_trunc('day', t0.event_unixtime, 'jst'), 'd!','jst') as "営業日"
    -- , if(f>=13, 13, f) as "F"
    -- , session_count as "セッション数/週"
  from
    _integration_datamart.z_tmp_cls_app_log_104w as t0
    left join _integration_datamart.z_tmp_cls_app_reserve as t1
      on t0.user_pseudo_id = t1.user_pseudo_id and t0.ga_session_id = t1.ga_session_id 
        and t0.event_name = t1.event_name and t0.event_timestamp = t1.event_timestamp
    left join app_session_master as t2
      on t0.user_pseudo_id = t2.user_pseudo_id and t0.ga_session_id = t2.ga_session_id
        and td_date_trunc('month', t0.event_unixtime, 'jst') = td_time_parse(t2.month, 'jst')
    left join id_map_by_reservation as t3
      on t0.user_pseudo_id = t3.user_pseudo_id
        and td_date_trunc('month', t0.event_unixtime, 'jst') = td_time_parse(t3.month, 'jst')
    left join customer_rf_shop as t4 on coalesce(t2.customer_id, t3.customer_id) = t4.customer_id and td_time_parse(t2.month, 'jst') = t4.time
    left join (
      select
        td_date_trunc('month', event_unixtime, 'jst') as month
        , user_pseudo_id
        , count(distinct ga_session_id) as session_count
      from
        _integration_datamart.z_tmp_cls_app_log_104w
      group by
        1,2
    ) as t5 on td_date_trunc('month', t0.event_unixtime, 'jst') = t5.month and t0.user_pseudo_id = t5.user_pseudo_id
  group by
    1,2,3
    -- 1,2,3,4,11,12,13
  order by
    1,2,3
)

select
  yom
  , moy
  , segment
  , app_session
  , app_session_uu
  , 1.0 * app_session_uu / sum(app_session_uu) over (partition by yom, moy) as app_session_uu_rate
  , reservation_complete_uu
from tmp
order by 1,2,3