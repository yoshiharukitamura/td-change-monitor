with customer_rf_shop as (
  select distinct
    time
    , customer_id
    , first_order_unixtime
    , r_week
    , shop_no_last_order
  from
    _integration_datamart.hst_weekly_customer_rf
    -- inner join (select time, customer_id from _integration_datamart.z_tmp_cls_reservation) using (time, customer_id)    
  where
    time >= td_date_trunc('week', td_time_parse('2025-01-01', 'jst'), 'jst')
)
, web_session_master as (
  select
    td_uid
    , ga_session_id
    , min(event_unixtime) as session_start_time
    , max_by(customer_id, if(customer_id is not null, event_unixtime, null)) as customer_id
    , max_by(shop_no, if(shop_no is not null, event_unixtime, null)) as shop_no
  from
    _integration_datamart.z_tmp_cls_web_log_104w
  where
    time >= td_date_trunc('week', td_time_parse('2025-01-01', 'jst'), 'jst')
  group by
    td_uid
    , ga_session_id
)
, prep_reservation_order as (
  select distinct
    reservation_id
    , customer_id
  from
    _integration_datamart.cls_order_detail
  where
    reservation_id is not null
    and time >= td_date_trunc('week', td_time_parse('2025-01-01', 'jst'), 'jst')
)
, prep_reservation as (
  select distinct
    id as reservation_id
    , customer_id
    , cast(shop_no as bigint) as shop_no
    , td_time_parse(created, 'jst') as created_unixtime
  from
    _l1_mysql_reservation.reservations
    left join (select parent_reservation_id as id, status as status_fixed from _l1_mysql_reservation.reservations where status = 0 and parent_reservation_id is not null) using (id)
    left join (select id as reservation_person_id, member_card_no from _l1_mysql_reservation.reservation_persons) using (reservation_person_id)
    left join (select id as customer_id, members_card_no as member_card_no from _l1_mysql_pos.customers) using (member_card_no)
    left join (select reservation_id as id, resource_timetable_id from _l1_mysql_reservation.reservation_relations) using (id)
    left join (select id as resource_timetable_id, mst_shop_id as property_id from _l1_mysql_reservation.resource_timetables) using (resource_timetable_id)
    left join (select property_id, shop_no from _integration_datamart.mst_shop) using (property_id)
  where
    deleted = 0
    and not (status = 0 and parent_reservation_id is not null)
    and parent_reservation_id is null
)

select
  td_time_string(td_date_trunc('week', t0.event_unixtime, 'jst'), 'd!','jst') as business_week
    , case
        when utm_medium = 'organic' and utm_source = 'google' then 'Search-Google'
        when utm_medium = 'organic' and utm_source = 'yahoo' then 'Search-Yahoo'
        when utm_medium = 'organic' then 'Search-Other'
        when utm_medium = 'map' and utm_source = 'google' then 'Map-Google'
        when utm_medium = 'map' and utm_source = 'yahoo' then 'Map-Yahoo'
        when utm_medium = 'map' then 'Map-Other'
        when regexp_like(utm_medium, '^(cpc|display)$') then 'Paid'
        when regexp_like(utm_source, '^(twitter|instagram|facebook|line)$') then 'Social'
        when utm_medium = '(none)' then '直接流入'
        else 'その他'
      end as traffic_source
  , case
      when coalesce(t2.customer_id, t3.customer_id, t4.customer_id) is null then 'ゲスト'
      when t2.session_start_time < coalesce(t5.first_order_unixtime, td_scheduled_time()) then '新規'
      when t2.session_start_time >= coalesce(t5.first_order_unixtime, td_scheduled_time()) then '既存'
      else '例外'
    end as new_repeat
  , case
      when r_week between 0 and 12 then 'R/w0-12'
      when r_week between 13 and 24 then 'R/w13-24'
      when r_week >= 25 then 'R/w25-'
      else 'null'
    end as r
  , shop_no_last_order as shop_no
  , count(distinct t0.ga_session_id) as session_count
  , count(distinct if(t0.event_status in (1,2,3,4), t0.td_uid, null)) as session_uu
  , count(distinct if(t0.event_status in (2,3,4), t0.td_uid, null)) as reservation_bahavior_uu
  , count(distinct if(t0.event_status in (3,4), t0.td_uid, null)) as reservation_confirm_uu
  , count(distinct if(t0.event_status in (4) and t4.created_unixtime between t0.event_unixtime - 300 and t0.event_unixtime + 300, t0.td_uid, null)) as reservation_complete_uu
  , count(distinct if(t0.event_status in (4) and t4.created_unixtime between t0.event_unixtime - 300 and t0.event_unixtime + 300, t4.reservation_id, null)) as reservation_order_count
from
  _integration_datamart.z_tmp_cls_web_log_104w as t0
  left join web_session_master as t2 on t0.td_uid = t2.td_uid and t0.ga_session_id = t2.ga_session_id
  left join prep_reservation_order as t3 on t0.reservation_id = t3.reservation_id
  left join prep_reservation as t4 on t0.reservation_id = t4.reservation_id
  left join customer_rf_shop as t5 on coalesce(t2.customer_id, t3.customer_id, t4.customer_id) = t5.customer_id and t0.time = t5.time
where
  t0.time >= td_date_trunc('week', td_time_parse('2025-01-01', 'jst'), 'jst')
group by
  1,2,3,4,5
order by
  1 desc,2,3,4,5
