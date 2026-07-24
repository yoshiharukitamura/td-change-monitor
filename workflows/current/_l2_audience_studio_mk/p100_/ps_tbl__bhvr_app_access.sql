with app_log as (
  select
    try_cast(regexp_extract(event_params, '{"key":"customer_id","value":{"string_value":"(\d+)"', 1) as bigint) as customer_id
    , time as access_datetime
    , try_cast(regexp_extract(event_params, '{"key":"shop_no","value":{"string_value":"(\d+)"', 1) as bigint) as shop_no
    , try_cast(regexp_extract(event_params, '{"key":"reservation_id","value":{"string_value":"(\d+)"', 1) as bigint) as reservation_id
    , regexp_extract(event_params, '{"key":"ga_session_id","value":{"string_value":null,"int_value":(\d+)', 1) as ga_session_id
    , regexp_extract(traffic_source, '"name":"([^"]+)"', 1) as utm_source_name
    , regexp_extract(traffic_source, '"medium":"([^"]+)"', 1) as utm_medium
    , regexp_extract(traffic_source, '"source":"([^"]+)"', 1) as utm_source
    , event_name
    , case event_name
        when 'onfocus_completed_booking_screen' then '予約完了'
        when 'g1_click_reserve_s3' then '予約完了'
        when 'menu_next' then '予約詳細（メニュー）'
        when 'calendar_history' then '予約行動'
        when 'calendar_nearest' then '予約行動'
        when 'top_nomination_calendar' then '予約行動'
        when 'top_time_shop_book_again' then '予約行動'
        when 'top_time_shop_book_again_cart' then '予約行動'
        when 'top_time_shop_near' then '予約行動'
        when 'top_time_shop_near_cart' then '予約行動'
        when 'top_nomination_time_cart' then '予約行動'
        when 'top_nomination_time' then '予約行動'
        when 'top_option' then '予約行動'
        when 'top_location' then '予約行動'
        when 'onfocus_shop_detail_screen' then '予約行動'
        when 'g1_click_reserve_s2' then '予約行動'
        when 'suggest_reserve1' then '予約行動'
        when 'suggest_reserve2' then '予約行動'
        when 'suggest_reserve3' then '予約行動'
        when 'HistoryBookingScreen' then '予約行動'
        when 'SearchScreen' then '予約行動'
        when 'onfocus_scan_qr_code_screen' then '予約行動'
        when 'tpranking_banner' then '予約行動'
        when 'All_Therapist_favorite' then '予約行動'
        when 'all_nearest_shops' then '予約行動'
        when 'all_history_shops' then '予約行動'
        when 'first_open' then 'その他'
        when 'app_remove' then 'その他'
        when 'app_update' then 'その他'
        when 'notification_dismiss' then 'その他'
        when 'notification_receive' then 'その他'
        when 'screen_view' then 'その他'
        when 'user_engagement' then 'その他'
        when 'tracking_token' then 'その他'
        when 'firebase_campaign' then 'その他'
        when 'notification_foreground' then 'その他'
        when 'notification_open' then 'その他'
        when 'os_update' then 'その他'
        else 'その他'
    end as event_status
    , count(1) as view
  from
    _l0_bigquery.firebase_event_log
  where
    td_interval(time, '-365d', 'jst')
  group by
    1,2,3,4,5,6,7,8,9,10
)

select
  customer_id as mstr__id
  , access_datetime as app_access_datetime
  , shop_name as app_shop_name
  , reservation_id as app_reservation_id
  , ga_session_id as app_session_id
  , utm_source_name as app_utm_source_name
  , utm_medium as app_utm_medium
  , utm_source as app_utm_source
  , event_name as app_event_name
  , event_status as app_event_status
  , view
from
  app_log
left join
  (select cast(shop_no as bigint) as shop_no, shop_name from _integration_datamart.mst_shop) using (shop_no)
where
  customer_id is not null