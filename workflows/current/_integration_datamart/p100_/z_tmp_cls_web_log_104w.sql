select
  td_date_trunc('day', access_time, 'jst') as time
  , 'start_date' as time_means
  , td_time_string(access_time, 'd!', 'jst') as access_date
  , access_time as event_unixtime
  , td_uid
  , customer_id
  , try_cast(regexp_extract(td_path, '/usr/shop/detail/(\d{4})', 1) as bigint) as shop_no
  , reservation_id
  , ga_session_id
  , referral_source
  , utm_source
  , utm_medium
  , utm_campaign
  , td_path
  , case
      when td_path = '/usr/reservations/complete' then 4
      when td_path = '/usr/reservations/confirm' then 3
      when regexp_like(td_path, '/usr/shop/detail/\d{4}') then 2
      when regexp_like(td_path, '/usr/shop/(search|lists)') then 2
      else 1
    end as event_status
from
  l1_website_access.trs_ga_session
  inner join ( select td_uid from l1_website_access.trs_ga_session group by td_uid having count(1)>=2 ) using (td_uid)
  left join (
      select td_uid, cast(max_by(customer_id, last_access_time) as bigint) as customer_id
      from l1_website_access.map_tduid_customerid
      group by td_uid
    ) using (td_uid)
  left join (
      select pv_id, reservation_id
      from _integration_datamart.z_tmp_cls_web_reserve
    ) using (pv_id)
where
  td_time_range(time, td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-105w'), td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '1d'), 'jst')
  and td_time_range(start_date, td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-104w'), td_date_trunc('day', td_scheduled_time(), 'jst'), 'jst')
  and td_host = 'relxle.com'