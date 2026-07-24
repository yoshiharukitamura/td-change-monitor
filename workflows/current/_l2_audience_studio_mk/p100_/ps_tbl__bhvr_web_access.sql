with web_access_log as (
  select
    case
      when t2.customer_id is null then coalesce(t0.td_uid, t1.td_uid, t2.td_uid)
      else t2.customer_id
    end as customer_id
    , time as access_datetime
    , try_cast(regexp_extract(td_path, '/usr/shop/detail/(\d{4})', 1) as bigint) as shop_no
    , reservation_id
    , ga_session_id
    , referral_source
    , utm_source
    , utm_medium
    , utm_campaign
    , td_url
    , td_path
    , case
        when td_path = '/usr/reservations/complete' then '予約完了'
        when td_path = '/usr/reservations/confirm' then '予約確認'
        when regexp_like(td_path, '/usr/shop/detail/\d{4}') then '店舗詳細'
        when regexp_like(td_path, '/usr/shop/(search|lists)') then '店舗詳細'
        else 'TOP（その他ページ）'
      end as event_status
    , count(1) as pv
  from
    l1_website_access.trs_ga_session as t0
  inner join 
    (select td_uid from l1_website_access.trs_ga_session group by td_uid having count(1)>=2) as t1
    on t0.td_uid = t1.td_uid
  left join (
      select td_uid, cast(max_by(customer_id, last_access_time) as bigint) as customer_id
      from l1_website_access.map_tduid_customerid
      group by td_uid
    ) as t2
    on t0.td_uid = t2.td_uid
  left join (
      select pv_id, reservation_id
      from _integration_datamart.z_tmp_cls_web_reserve
    ) as t3
    on t0.pv_id = t3.pv_id
where
  td_interval(t0.time, '-365d', 'jst')
group by
  1,2,3,4,5,6,7,8,9,10,11,12
)

select
  customer_id as mstr__id
  , access_datetime as web_access_datetime
  , shop_name as web_shop_name
  , reservation_id as web_reservation_id
  , ga_session_id as web_session_id
  , referral_source as web_referral_source
  , utm_source as web_utm_source
  , utm_medium as web_utm_medium
  , utm_campaign as web_utm_campaign
  , td_url
  , td_path
  , event_status as web_event_status
  , pv
from
  web_access_log
left join
  (select cast(shop_no as bigint) as shop_no, shop_name from _integration_datamart.mst_shop) using (shop_no)