drop table if exists l2_tp_suggest.suggest_verification;
create table l2_tp_suggest.suggest_verification as 

with suggest_ts as (
  select
    therapist_no
    , therapist_id
    , pattern
    , td_time_string(td_date_trunc('week', td_time_parse(entry_from, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , substr(entry_from, 1, 10) as business_date
    , shop_no
    , shop_name
    , h as business_hour
    , 1 as suggest_hour_type
  from l2_tp_suggest.suggest_history_v2
  cross join unnest(sequence(suggeststart1, suggestend1)) as t(h)
  left join (select therapist_no, therapist_id from _integration_datamart.mst_therapist) using (therapist_no)
  where substr(entry_from, 1, 10) >= '2025-06-05'
  union all
  select
    therapist_no
    , therapist_id
    , pattern
    , td_time_string(td_date_trunc('week', td_time_parse(entry_from, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , substr(entry_from, 1, 10) as business_date
    , shop_no
    , shop_name
    , h as business_hour
    , 2 as suggest_hour_type
  from l2_tp_suggest.suggest_history_v2
  cross join unnest(sequence(suggeststart2, suggestend2)) as t(h)
  left join (select therapist_no, therapist_id from _integration_datamart.mst_therapist) using (therapist_no)
  where substr(entry_from, 1, 10) >= '2025-06-05'
)

, suggest_entry_ts as (
  select
    therapist_no
    , therapist_id
    , pattern
    , business_week
    , business_date
    , shop_no
    , property_id
    , shop_name
    , business_hour
    , suggest_hour_type
    , if(entry_slot = 1.0, 1, 0) as is_entry
  from suggest_ts
  left join (
    select 
      therapist_no
      , therapist_id
      , business_date
      , property_id
      , cast(shop_no as int) as shop_no
      , business_hour
      , entry_slot
    from _integration_datamart.cls_time_slot_detail
    where substr(business_date, 1, 10) >= '2025-06-05'
   ) using (therapist_no, therapist_id, shop_no, business_date, business_hour)
)

, prep_mail_open as (
  select
    distinct
    suggest_date as business_date
    , therapist_id
    , 1 as is_mail_open
    , td_time_parse(open_datetime, 'jst') as mail_open_unixtime
  from
    l2_tp_suggest.log_mail_open
    --mail開封とリンクURLアクセスの紐付けのためにtherapist_idを取得
    left join (
        select therapist_id, email
        from _l0_mysql_core.therapist_contact
        inner join (
          select therapist_id, max(time) as time
          from _l0_mysql_core.therapist_contact
          group by therapist_id
        ) using (therapist_id, time)
      ) using (email)
)

, prep_weblog as (
  select
    therapistno as therapist_no
    , try_cast(regexp_extract(td_url, '/EntrySlot/([^/]+)/([^/]+)', 1) as int) as property_id
    , date_format(date_trunc('week', 
        try(date_parse(regexp_extract(td_url, '/EntrySlot/[0-9]+/([0-9]{4}-[0-9]{1,2}-[0-9]{1,2})(?:[/?#]|$)', 1), '%Y-%c-%e'))), '%Y-%m-%d') as business_week
    , time as access_time
  from
    l0_website_access.pv_log_therapist
  where
    regexp_like(td_url, 'EntrySlot')
    and time >= td_time_parse('2025-06-05', 'jst')
)

, prep_weblog_info as (
  select
    distinct
    therapist_no
    , therapist_id
    , property_id
    , cast(shop_no as int) as shop_no
    , business_week
    , access_time
  from
    prep_weblog
    left join (select shop_no, property_id from _integration_datamart.mst_shop) using (property_id)
    --mail開封とリンクURLアクセスの紐付けのためにtehrapist_idを取得
    left join (select therapist_no, therapist_id from _integration_datamart.mst_therapist) using (therapist_no)
)

, prep_mail_access as (
  select distinct
    business_date
    , t0.therapist_id
    , shop_no
    , property_id
    , coalesce(url_access, 0) as is_url_access
  from
    prep_mail_open as t0
    left join (
      select 
        therapist_id
        , therapist_no
        , property_id
        , shop_no
        , access_time
        , 1 as url_access
      from prep_weblog_info
      ) as t1
      on t0.therapist_id = t1.therapist_id
         --メール開封→リンクURLアクセスの定義　再ログインが必要なので、1時間に設定
         and t1.access_time between t0.mail_open_unixtime and t0.mail_open_unixtime + 60*60*1
)

, merged as (
  select
    therapist_no
    , therapist_id
    , pattern
    , business_week
    , business_date
    , shop_no
    , shop_name
    , business_hour
    , suggest_hour_type
    , coalesce(is_entry, 0) as is_entry
    , coalesce(is_mail_open, 0) as is_mail_open
    , coalesce(is_url_access, 0) as is_url_access
  from suggest_entry_ts
  left join prep_mail_open using (therapist_id, business_date)
  left join prep_mail_access using (therapist_id, property_id, shop_no, business_date)
  group by 1,2,3,4,5,6,7,8,9,10,11,12
)
select
  business_date
  , count(distinct therapist_no) as suggest_uu
  , count(distinct if(is_mail_open = 1, therapist_no, null)) as mail_open_uu
  , count(distinct if(is_url_access = 1, therapist_no, null)) as url_access_uu
  , sum(1) as mail_open_slot
  , sum(if(suggest_hour_type = 1, 1, 0)) as mail_open_slot_1
  , sum(if(suggest_hour_type = 2, 1, 0)) as mail_open_slot_2
  , sum(if(is_entry = 1, 1, 0)) as entry_slot
  , sum(if(is_entry = 1 and suggest_hour_type = 1, 1, 0)) as entry_slot_1
  , sum(if(is_entry = 1 and suggest_hour_type = 2, 1, 0)) as entry_slot_2
  , sum(if(is_mail_open = 1 and is_entry = 1, 1, 0)) as entry_slot_mailop
  , sum(if(is_mail_open = 1 and is_entry = 1 and suggest_hour_type = 1, 1, 0)) as entry_slot_mailop_1
  , sum(if(is_mail_open = 1 and is_entry = 1 and suggest_hour_type = 2, 1, 0)) as entry_slot_mailop_2
  , sum(if(is_mail_open = 1 and is_url_access = 1 and is_entry = 1, 1, 0)) as entry_slot_mailop_urlac
  , sum(if(is_mail_open = 1 and is_url_access = 1 and is_entry = 1 and suggest_hour_type = 1, 1, 0)) as entry_slot_mailop_urlac_1
  , sum(if(is_mail_open = 1 and is_url_access = 1 and is_entry = 1 and suggest_hour_type = 2, 1, 0)) as entry_slot_mailop_urlac_2
from merged
group by 1
order by 1