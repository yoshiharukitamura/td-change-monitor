with customer_rf_shop as (
  select distinct
    time
    , customer_id
    , first_order_unixtime
    , r_week
    , f
  from
    _integration_datamart.hst_weekly_customer_rf
)
, app_session_master as (
  select
    user_pseudo_id
    , ga_session_id
    , td_time_string(week, 'd!', 'jst') as week
    , customer_id
    , shop_no
    , traffic_source_medium
  from (
      select distinct user_pseudo_id, ga_session_id, td_date_trunc('week', event_unixtime, 'jst') as week
      from _integration_datamart.z_tmp_cls_app_log_104w
    )
    left join (
        select user_pseudo_id, td_date_trunc('week', event_unixtime, 'jst') as week, max_by(customer_id, event_unixtime) as customer_id
        from _integration_datamart.z_tmp_cls_app_log_104w
        where customer_id is not null
        group by 1,2
      ) using (user_pseudo_id, week)
    left join (
        select user_pseudo_id, td_date_trunc('week', event_unixtime, 'jst') as week, max_by(shop_no, event_unixtime) as shop_no
        from _integration_datamart.z_tmp_cls_app_log_104w
        where shop_no is not null
        group by 1,2
      ) using (user_pseudo_id, week)
    left join (
        select user_pseudo_id, td_date_trunc('week', event_unixtime, 'jst') as week, min_by(traffic_source_medium, event_unixtime) as traffic_source_medium
        from _integration_datamart.z_tmp_cls_app_log_104w
        group by 1,2
      ) using (user_pseudo_id, week)
)
, sys_reservation as (
  select reservation_id, customer_id
  from _integration_datamart.z_tmp_cls_reservation
  where reserved_from = 'APP' and parent_reservation_id is null
)
, id_map_by_reservation as (
  select
    user_pseudo_id
    , td_time_string(td_date_trunc('week', event_unixtime, 'jst'), 'd!','jst') as week
    , max_by(customer_id, event_unixtime) as customer_id
  from
    _integration_datamart.z_tmp_cls_app_reserve
    inner join sys_reservation using (reservation_id)
  where
    customer_id is not null
  group by
    1,2
)

, tmp as (
  select
    year_of_week(date(td_time_string(td_date_trunc('week', t0.event_unixtime, 'jst'), 'd!', 'jst'))) as yow
    , week_of_year(date(td_time_string(td_date_trunc('week', t0.event_unixtime, 'jst'), 'd!', 'jst'))) as woy
    , case
        when coalesce(t2.customer_id, t3.customer_id) is null then '01_新規(非会員)'
        when td_time_parse(t2.week, 'jst') <= td_date_trunc('week', coalesce(t4.first_order_unixtime, td_scheduled_time()), 'jst') then '02_新規(会員)'
        when r_week between 1 and 4 then '03_R/w1-4'
        when r_week between 5 and 8 then '04_R/w5-8'
        when r_week between 9 and 12 then '05_R/w9-12'
        when r_week between 13 and 24 then '06_R/w13-24'
        when r_week between 25 and 52 then '07_R/w24-52'
        when r_week >= 53 then '08_R/w53-'
      end as r_week
    , case
        when f between 1 and 5 then 'F1-5'
        when f >= 6 then 'F6-'
        else '-'
      end as f
    , case
        when session_count = 0 then 'S0'
        when session_count between 1 and 3 then 'S1-3'
        when session_count between 4 and 7 then 'S4-7'
        when session_count >= 8 then 'S8-'
      end as app_session_weekly
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
        and td_date_trunc('week', t0.event_unixtime, 'jst') = td_time_parse(t2.week, 'jst')
    left join id_map_by_reservation as t3
      on t0.user_pseudo_id = t3.user_pseudo_id
        and td_date_trunc('week', t0.event_unixtime, 'jst') = td_time_parse(t3.week, 'jst')
    left join customer_rf_shop as t4 on coalesce(t2.customer_id, t3.customer_id) = t4.customer_id and td_time_parse(t2.week, 'jst') = t4.time
    left join (
      select
        td_date_trunc('week', event_unixtime, 'jst') as week
        , user_pseudo_id
        , count(distinct ga_session_id) as session_count
      from
        _integration_datamart.z_tmp_cls_app_log_104w
      group by
        1,2
    ) as t5 on td_date_trunc('week', t0.event_unixtime, 'jst') = t5.week and t0.user_pseudo_id = t5.user_pseudo_id
  group by
    1,2,3,4,5
    -- 1,2,3,4,11,12,13
  order by
    1,2,3,4,5
)


select
  yow
  , woy
  , r_week
  , f
  , app_session_weekly
  , app_session
  , app_session_uu
  , 1.0 * app_session_uu / sum(app_session_uu) over (partition by yow, woy) as app_session_uu_rate
  , reservation_complete_uu
from tmp
order by 1,2,3