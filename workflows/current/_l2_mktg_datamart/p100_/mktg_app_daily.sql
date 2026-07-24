with customer_rf_shop as (
  select distinct
    time
    , customer_id
    , first_order_unixtime
    , r_week
    , f
    , shop_no_last_order
  from
    _integration_datamart.hst_daily_customer_rf
    -- inner join (select time, customer_id from _integration_datamart.z_tmp_cls_reservation) using (time, customer_id)    
  where
    td_time_range(time, td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-12w'), td_date_trunc('day', td_scheduled_time(), 'jst'), 'jst')
)
, app_session_master as (
  select
    user_pseudo_id
    , ga_session_id
    , td_time_string(day, 'd!', 'jst') as day
    , customer_id
    , shop_no
    , traffic_source_medium
  from (
      select distinct user_pseudo_id, ga_session_id, td_date_trunc('day', event_unixtime, 'jst') as day
      from _integration_datamart.z_tmp_cls_app_log_104w
    )
    left join (
        select user_pseudo_id, td_date_trunc('day', event_unixtime, 'jst') as day, max_by(customer_id, event_unixtime) as customer_id
        from _integration_datamart.z_tmp_cls_app_log_104w
        where customer_id is not null
        group by 1,2
      ) using (user_pseudo_id, day)
    left join (
        select user_pseudo_id, td_date_trunc('day', event_unixtime, 'jst') as day, max_by(shop_no, event_unixtime) as shop_no
        from _integration_datamart.z_tmp_cls_app_log_104w
        where shop_no is not null
        group by 1,2
      ) using (user_pseudo_id, day)
    left join (
        select user_pseudo_id, td_date_trunc('day', event_unixtime, 'jst') as day, min_by(traffic_source_medium, event_unixtime) as traffic_source_medium
        from _integration_datamart.z_tmp_cls_app_log_104w
        group by 1,2
      ) using (user_pseudo_id, day)
)
, sys_reservation as (
  select reservation_id, customer_id
  from _integration_datamart.z_tmp_cls_reservation_daily
  where reserved_from = 'APP' and parent_reservation_id is null
)
, id_map_by_reservation as (
  select
    user_pseudo_id
    , td_time_string(td_date_trunc('day', event_unixtime, 'jst'), 'd!','jst') as day
    , max_by(customer_id, event_unixtime) as customer_id
  from
    _integration_datamart.z_tmp_cls_app_reserve
    inner join sys_reservation using (reservation_id)
  where
    customer_id is not null
  group by
    1,2
)
, id_map_by_reservation_nw as (
  select
    user_pseudo_id
    , td_time_string(td_time_add(td_date_trunc('day', event_unixtime, 'jst'), '-7d', 'jst'), 'd!','jst') as day
    , max_by(customer_id, event_unixtime) as customer_id
    , 1 as nw_reserve
  from
    _integration_datamart.z_tmp_cls_app_reserve
    inner join sys_reservation using (reservation_id)
  where
    customer_id is not null
  group by
    1,2
)

, app_session_nw as 
(
 select
   user_pseudo_id
   , td_time_string(td_time_add(td_date_trunc('day', event_unixtime, 'jst'), '-7d', 'jst'), 'd!','jst') as day
   --, event_status
   , max_by(customer_id, event_unixtime) as customer_id
   , 1 as nw_session
   from _integration_datamart.z_tmp_cls_app_log_104w
   group by 1,2
)

select
  td_time_string(td_date_trunc('day', t0.event_unixtime, 'jst'), 'd!', 'jst') as business_day
  , case
      when t2.traffic_source_medium = 'organic' then '直接流入'
      when t2.traffic_source_medium = '(none)' then '直接流入'
      when t2.traffic_source_medium = 'cpc' then 'Paid'
      when t2.traffic_source_medium = 'map' then 'Map'
      else 'その他'
    end as traffic_source
  , case
      when coalesce(t2.customer_id, t3.customer_id) is null then 'ゲスト'
      when td_time_parse(t2.day, 'jst') <= td_date_trunc('day', coalesce(t4.first_order_unixtime, td_scheduled_time()), 'jst') then '新規'
      when td_time_parse(t2.day, 'jst') > td_date_trunc('day', coalesce(t4.first_order_unixtime, td_scheduled_time()), 'jst') then '既存'
      else '例外'
    end as new_repeat
  , case
      when r_week between 0 and 12 then 'R/w0-12'
      when r_week between 13 and 24 then 'R/w13-24'
      when r_week >= 25 then 'R/w25-'
      else 'null'
    end as r
  , shop_no_last_order as shop_no
  , count(distinct t0.user_pseudo_id||t0.ga_session_id) as session_count
  , count(distinct if(t0.event_status in (1,2,3,4), t0.user_pseudo_id, null)) as session_uu
  , count(distinct if(t0.event_status in (2,3,4), t0.user_pseudo_id, null)) as reservation_bahavior_uu
  , count(distinct if(t0.event_status in (3,4), t0.user_pseudo_id, null)) as reservation_confirm_uu
  , count(distinct if(t0.event_status in (4), t0.user_pseudo_id, null)) as reservation_complete_uu
  , count(distinct if(t0.event_status in (4), t1.reservation_id, null)) as reservation_order_count
  , count(distinct if(nw_reserve = 1, t0.user_pseudo_id, null)) 
      - count(distinct if(nw_reserve = 1 and t0.event_status in (4), t0.user_pseudo_id, null)) as nw_reservation_complete_uu
  , count(distinct if(nw_session = 1, t0.user_pseudo_id, null)) 
      - count(distinct if(nw_session = 1 and t0.event_status in (4), t0.user_pseudo_id, null)) as nw_session_uu_not_reservation
  -- , td_time_string(td_date_trunc('day', t0.event_unixtime, 'jst'), 'd!','jst') as business_date
  -- , if(f>=13, 13, f) as f
  -- , session_count as week_session_count
from
  _integration_datamart.z_tmp_cls_app_log_104w as t0
  left join app_session_nw as t01 
    on t0.user_pseudo_id = t01.user_pseudo_id
      and td_date_trunc('day', t0.event_unixtime, 'jst') = td_time_parse(t01.day, 'jst')
  left join _integration_datamart.z_tmp_cls_app_reserve as t1
    on t0.user_pseudo_id = t1.user_pseudo_id and t0.ga_session_id = t1.ga_session_id 
      and t0.event_name = t1.event_name and t0.event_timestamp = t1.event_timestamp
  left join app_session_master as t2
    on t0.user_pseudo_id = t2.user_pseudo_id and t0.ga_session_id = t2.ga_session_id
      and td_date_trunc('day', t0.event_unixtime, 'jst') = td_time_parse(t2.day, 'jst')
  left join id_map_by_reservation as t3
    on t0.user_pseudo_id = t3.user_pseudo_id
      and td_date_trunc('day', t0.event_unixtime, 'jst') = td_time_parse(t3.day, 'jst')
  left join id_map_by_reservation_nw as t31
    on t0.user_pseudo_id = t31.user_pseudo_id
      and td_date_trunc('day', t0.event_unixtime, 'jst') = td_time_parse(t31.day, 'jst')
  left join customer_rf_shop as t4 on coalesce(t2.customer_id, t3.customer_id) = t4.customer_id and td_time_parse(t2.day, 'jst') = t4.time
  left join (
    select
      td_date_trunc('day', event_unixtime, 'jst') as day
      , user_pseudo_id
      , count(distinct ga_session_id) as session_count
    from
      _integration_datamart.z_tmp_cls_app_log_104w
    group by
      1,2
  ) as t5 on td_date_trunc('day', t0.event_unixtime, 'jst') = t5.day and t0.user_pseudo_id = t5.user_pseudo_id
where
  td_time_range(t0.time, td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-12w'), td_date_trunc('day', td_scheduled_time(), 'jst'), 'jst')
group by
  -- 1,2,3,4,11,12,13
  1,2,3,4,5
order by
  -- 1 desc,11,12,13,2,3,4
  1 desc,2,3,4,5
