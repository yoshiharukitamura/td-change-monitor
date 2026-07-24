select
  time
  , 'event_date' as time_means
  , event_date as access_date
  , event_unixtime
  , event_timestamp_micros as event_timestamp
  , user_pseudo_id
  , try_cast(regexp_extract(event_params, '{"key":"customer_id","value":{"string_value":"(\d+)"', 1) as bigint) as customer_id
  , try_cast(regexp_extract(event_params, '{"key":"shop_no","value":{"string_value":"(\d+)"', 1) as bigint) as shop_no
  , try_cast(regexp_extract(event_params, '{"key":"reservation_id","value":{"string_value":"(\d+)"', 1) as bigint) as reservation_id
  , regexp_extract(event_params, '{"key":"ga_session_id","value":{"string_value":null,"int_value":(\d+)', 1) as ga_session_id
  , regexp_extract(traffic_source, '"name":"([^"]+)"', 1) as traffic_source_name
  , regexp_extract(traffic_source, '"medium":"([^"]+)"', 1) as traffic_source_medium
  , regexp_extract(traffic_source, '"source":"([^"]+)"', 1) as traffic_source_source
  , event_name
  , case event_name
      when 'onfocus_completed_booking_screen' then 5
      when 'g1_click_reserve_s3' then 4
      when 'menu_next' then 3
      when 'calendar_history' then 2
      when 'calendar_nearest' then 2
      when 'top_nomination_calendar' then 2
      when 'top_time_shop_book_again' then 2
      when 'top_time_shop_book_again_cart' then 2
      when 'top_time_shop_near' then 2
      when 'top_time_shop_near_cart' then 2
      when 'top_nomination_time_cart' then 2
      when 'top_nomination_time' then 2
      when 'top_option' then 2
      when 'top_location' then 2
      when 'onfocus_shop_detail_screen' then 2
      when 'g1_click_reserve_s2' then 2
      when 'suggest_reserve1' then 2
      when 'suggest_reserve2' then 2
      when 'suggest_reserve3' then 2
      when 'HistoryBookingScreen' then 2
      when 'SearchScreen' then 2
      when 'onfocus_scan_qr_code_screen' then 2
      when 'tpranking_banner' then 2
      when 'All_Therapist_favorite' then 2
      when 'all_nearest_shops' then 2
      when 'all_history_shops' then 2
      when 'first_open' then null
      when 'app_remove' then null
      when 'app_update' then null
      when 'notification_dismiss' then  null
      when 'notification_receive' then  null
      when 'screen_view' then  null
      when 'user_engagement' then  null
      when 'tracking_token' then  null
      when 'firebase_campaign' then  null
      when 'notification_foreground' then  null
      when 'notification_open' then  null
      when 'os_update' then  null
      else 1
    end as event_status
from
  _l0_bigquery.firebase_event_log
where
  td_time_range(time, td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-157w'), td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '1d'), 'jst')
  and not regexp_like(event_name, 'first_open|app_(remove|update)|notification_(dismiss|receive|foreground|open)|screen_view|user_engagement|tracking_token|firebase_campaign|os_update')