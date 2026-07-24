with customer_rf_shop as (
  select distinct
    time
    , customer_id
    , first_order_unixtime
    , r_week
    , f
  from
    _integration_datamart.hst_weekly_customer_rf_w12f
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
    , week
    , customer_id
    , min(week) over (partition by user_pseudo_id order by week) as first_reserve_week
  from (
    select
      user_pseudo_id
      , td_time_string(td_date_trunc('week', event_unixtime, 'jst'), 'd!','jst') as week
      , max_by(customer_id, event_unixtime) as customer_id
    from
      _integration_datamart.z_tmp_cls_app_reserve
      inner join sys_reservation using (reservation_id)
    group by
      1,2
  )
)

, agg as (
  select
    year_of_week(date(td_time_string(td_date_trunc('week', t0.event_unixtime, 'jst'), 'd!', 'jst'))) as yow
    , week_of_year(date(td_time_string(td_date_trunc('week', t0.event_unixtime, 'jst'), 'd!', 'jst'))) as woy
    , case
        when coalesce(t2.customer_id, t3.customer_id) is null and t3.week = t3.first_reserve_week then '01_非会員（新規）'
        when coalesce(t2.customer_id, t3.customer_id) is null 
          and date_diff('week', date(t3.first_reserve_week), date(t3.week)) between 1 and 12 then '02_非会員_新規（オンボーディング）'
        when coalesce(t2.customer_id, t3.customer_id) is null 
          and date_diff('week', date(t3.first_reserve_week), date(t3.week)) >= 13 then '03_非会員（既存）'
        when coalesce(t2.customer_id, t3.customer_id) is null then '04_非会員（不明）'
        when td_time_parse(t2.week, 'jst') <= td_date_trunc('week', coalesce(t4.first_order_unixtime, td_scheduled_time()), 'jst') then '05_新規（当週）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', t4.first_order_unixtime, 'jst'), 'd!', 'jst')), date(t2.week)) between 1 and 12 then '06_新規（オンボーディング）'
        
        when date_diff('week', date(td_time_string(td_date_trunc('week', t4.first_order_unixtime, 'jst'), 'd!', 'jst')), date(t2.week)) >= 13 and
          r_week between 1 and 12 and f = 1 then '11_既存_ライト（12wF1）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', t4.first_order_unixtime, 'jst'), 'd!', 'jst')), date(t2.week)) >= 13 and
          r_week between 1 and 12 and f = 2 then '12_既存_ミドル（12wF2）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', t4.first_order_unixtime, 'jst'), 'd!', 'jst')), date(t2.week)) >= 13 and
          r_week between 1 and 12 and f >= 3 then '13_既存_ヘビー（12wF3+）'
        when r_week between 13 and 52 and f = 0 then '14_疎遠（R/w13-52）'
        when r_week >= 53 and f = 0 then '15_離反（R/w53+）'
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
    1,2,3
    -- 1,2,3,4,11,12,13
  order by
    1,2,3
)

, agg__app_web as (
  select
    year_of_week(date(td_time_string(td_date_trunc('week', t0.event_unixtime, 'jst'), 'd!', 'jst'))) as yow
    , week_of_year(date(td_time_string(td_date_trunc('week', t0.event_unixtime, 'jst'), 'd!', 'jst'))) as woy
    , case
        when coalesce(t2.customer_id, t3.customer_id) is null and t3.week = t3.first_reserve_week then '01_非会員（新規）'
        when coalesce(t2.customer_id, t3.customer_id) is null 
          and date_diff('week', date(t3.first_reserve_week), date(t3.week)) between 1 and 12 then '02_非会員_新規（オンボーディング）'
        when coalesce(t2.customer_id, t3.customer_id) is null 
          and date_diff('week', date(t3.first_reserve_week), date(t3.week)) >= 13 then '03_非会員（既存）'
        when coalesce(t2.customer_id, t3.customer_id) is null then '04_非会員（不明）'

        when r_week is null and t6.customer_id is not null and (member_type = 'APP会員' or member_type is null) and nonmember_history_flag = 0 then '07_APP会員（新規）'
        when r_week is null and t6.customer_id is not null and (member_type = 'APP会員' or member_type is null) and nonmember_history_flag = 1 then '08_APP会員（既存）'
        when r_week is null and t6.customer_id is not null and member_type = 'WEB会員' and nonmember_history_flag = 0 then '09_WEB会員（新規）'
        when r_week is null and t6.customer_id is not null and member_type = 'WEB会員' and nonmember_history_flag = 1 then '10_WEB会員（既存）'
        else 'その他'
      end as segment
    , count(distinct t0.user_pseudo_id||t0.ga_session_id) as app_session
    , count(distinct if(t0.event_status in (1,2,3,4), t0.user_pseudo_id, null)) as app_session_uu
    , count(distinct if(t0.event_status in (4), t0.user_pseudo_id, null)) as reservation_complete_uu      
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
    left join (
      select
        processing_date
        , customer_id
        , member_type
        , nonmember_history_flag
      from
        _integration_datamart.z_tmp_kpi_rf_base
    ) as t6 on coalesce(t2.customer_id, t3.customer_id) = t6.customer_id and td_time_parse(t2.week, 'jst') = td_time_parse(t6.processing_date, 'jst') 
  group by
    1,2,3
)

, agg__fixed as (
  select * from agg
   union all
  select * from agg__app_web where segment in ('07_APP会員（新規）', '08_APP会員（既存）', '09_WEB会員（新規）', '10_WEB会員（既存）') and yow >= 2026 and woy >= 26
)

select
  yow
  , woy
  , segment
  , case
      when segment in ('09_WEB会員（新規）', '10_WEB会員（既存）') then 0
      else app_session
    end as app_session
  , case
      when segment in ('09_WEB会員（新規）', '10_WEB会員（既存）') then 0
      else app_session_uu
    end as app_session_uu
  , 1.0 * app_session_uu / sum(app_session_uu) over (partition by yow, woy) as app_session_uu_rate
  , reservation_complete_uu
from agg__fixed
where yow >= 2024
order by 1,2,3