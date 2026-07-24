delete from l2_verification.tmp_kpi__app_funnel where time >= td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-1w', 'jst');
insert into l2_verification.tmp_kpi__app_funnel

with app_log as (
  select
    cast(regexp_extract(event_params, '{"key":"customer_id","value":{"string_value":"(\d+)"', 1) as bigint) as customer_id
    , user_pseudo_id
    , regexp_extract(event_params, '{"key":"ga_session_id","value":{"string_value":null,"int_value":(\d+)', 1) as ga_session_id
    , td_time_string(td_date_trunc('week', event_unixtime, 'jst'), 'd!', 'jst') as week
    , event_name
    , cast(regexp_extract(event_params, '{"key":"shop_no","value":{"string_value":"(\d+)"', 1) as varchar) as mst_shop_no
    , cast(regexp_extract(event_params, '{"key":"reservation_id","value":{"string_value":"(\d+)"', 1) as bigint) as reservation_id
  from
    _l0_bigquery.firebase_event_log
  where
    event_unixtime >= td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-1w', 'jst')
    and event_unixtime < td_date_trunc('week', td_scheduled_time(), 'jst')
)

select
  td_time_parse(week, 'jst') as time
  , week
  , count(if(regexp_like(event_name, 'onfocus_top_screen'), 1, null)) as pv
  , count(distinct user_pseudo_id) as uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s1'), user_pseudo_id, null)) as form_uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s2'), user_pseudo_id, null)) as confirm_uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s3'), user_pseudo_id, null)) as complete_uu
  , count(if(regexp_like(event_name, 'onfocus_top_screen') and customer_id is not null, 1, null)) as customer_pv
  , count(distinct customer_id) as customer_uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s1'), customer_id, null)) as form_customer_uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s2'), customer_id, null)) as confirm_customer_uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s3'), customer_id, null)) as complete_customer_uu
  , count(if(regexp_like(event_name, 'onfocus_top_screen') and customer_id is null, 1, null)) as anonymous_pv
  , count(distinct if(customer_id is null, user_pseudo_id, null)) as anonymous_uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s1') and customer_id is null, user_pseudo_id, null)) as form_anonymous_uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s2') and customer_id is null, user_pseudo_id, null)) as confirm_anonymous_uu
  , count(distinct if(regexp_like(event_name, 'g1_click_reserve_s3') and customer_id is null, user_pseudo_id, null)) as complete_anonymous_uu
from
  app_log
group by
  1,2
order by
  1 desc
;

select
  week
  , pv
  , uu
  , form_uu
  , confirm_uu
  , complete_uu
  , customer_pv
  , customer_uu
  , form_customer_uu
  , confirm_customer_uu
  , complete_customer_uu
  , anonymous_pv
  , anonymous_uu
  , form_anonymous_uu
  , confirm_anonymous_uu
  , complete_anonymous_uu
from
  l2_verification.tmp_kpi__app_funnel
order by
  1
