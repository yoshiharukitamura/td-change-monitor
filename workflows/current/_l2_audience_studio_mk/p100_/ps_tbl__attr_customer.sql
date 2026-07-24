with customers as (
  select
    customer_id
  from (
    select dtb_customer_id as customer_id from _l1_mysql_hp.customers where coalesce(deleted, 0) = 0 group by 1
     union all
    select id as customer_id from _l1_mysql_pos.customers where coalesce(deleted, 0) = 0 and coalesce(deactivated, 0) = 0 group by 1
  )
  group by
    1
)

, customer_info_hp as (
  select
    dtb_customer_id as customer_id
    , concat(last_name_kanji, ' ', first_name_kanji) as customer_name
    , null as membership_no
    , null as gender
    , null as age
    , null as birth_date
    , null as birth_month
    , null as membership_channel
    , null as membership_senior
    , 1 as membership_royal
    , case
        when last_order_date is not null then 1
        else 0
      end as new_or_repeat
    , td_time_parse(created, 'jst') as registered_date_datetime
    , phone_no
    , name as prefecture
    , null as zip_code
    , case
        when push_noti = 1 then 1
        else 0
      end as push_permission
    , case
        when mailflg = 1 then 1
        else 0
      end as mail_permission
  from
    _l1_mysql_hp.customers
  left join
    (select customer_id as dtb_customer_id, max(purchased_datetime) as last_order_date from _l1_mysql_pos.orders group by 1) using (dtb_customer_id)
  left join
    (select id as pref_id, name from _l1_mysql_hp.pref) using (pref_id)
  where
    coalesce(deleted, 0) = 0
)

, prep_current_day as (
  select
    td_time_string(td_scheduled_time(), 'd!', 'jst') as business_date
)

, customer_info_pos as (
  select
    id as customer_id
    , name as customer_name
    , members_card_no as membership_no
    , case
        when gender = 1 then '男性'
        when gender = 2 then '女性'
        else '不明'
      end as gender
    , case 
        when birth_date is null then null
        else 
          date_diff('year', date(substr(birth_date, 1, 10)), date(business_date)) 
            - case
                when date_add('year', date_diff('year', date(substr(birth_date, 1, 10)), date(business_date)), date(substr(birth_date, 1, 10))) > date(business_date)
                then 1 
                else 0
              end
      end as age
    , substr(birth_date, 1, 10) as birth_date
    , substr(birth_date, 6, 2) as birth_month
    , case
        when is_app_user = 1 then 'アプリ'
        when is_app_user = 0 and is_senior_member = 0 then 'カード'
        else null
      end as membership_channel
    , case
        when is_senior_member = 1 then 'シニア'
        else null
      end as membership_senior
    , 1 as membership_royal
    , case
        when last_order_date is not null then 1
        else 0
      end as new_or_repeat
    , td_time_parse(created, 'jst') as registered_date_datetime
    , phone_no
    , pref_name as prefecture
    , concat(zip_code1, '-', zip_code2) as zip_code
    , null as push_permission
    , case
        when mail_magazine = 3 then 1
        else 0
      end as mail_permission
  from
    _l1_mysql_pos.customers
  left join
    (select customer_id as id, max(purchased_datetime) as last_order_date from _l1_mysql_pos.orders group by 1) using (id)
  left join
    (select id as pref_id, name as pref_name from _l1_mysql_hp.pref) using (pref_id)
  cross join
    prep_current_day
  where
    coalesce(deleted, 0) = 0
    and coalesce(deactivated, 0) = 0
)

, merged as (
  select * from customer_info_hp
   union all
  select * from customer_info_pos
)

, email_mst as (
  select
    cast(customer_id as integer) as customer_id
    , lower(email) as email
  from
    _l0_s3.customer_emails
  inner join
    (select customer_id, max(time) as time from _l0_s3.customer_emails group by 1) using (customer_id, time)
)

select
  customer_id as mstr__id
  , max(customer_name) as customer_name
  , max(membership_no) as membership_no
  , max(gender) as gender
  , max(age) as age
  , max(birth_date) as birth_date
  , max(birth_month) as birth_month
  , max(membership_channel) as membership_channel
  , max(membership_senior) as membership_senior
  , max(membership_royal) as membership_royal
  , case
      when max(new_or_repeat) = 1 then '既存'
      else '新規'
    end as new_or_repeat
  , min(registered_date_datetime) as registered_date_datetime
  , email
  , to_hex(sha256(to_utf8(email))) as hex_email
  , max(phone_no) as phone_no
  , regexp_replace(max(phone_no), '^0', '81') as format_phone_no
  , to_hex(sha256(to_utf8(regexp_replace(max(phone_no), '^0', '81')))) as hex_format_phone_no
  , max(prefecture) as prefecture
  , max(zip_code) as zip_code
  , case
      when max(push_permission) = 1 then '許諾あり'
      else '許諾なし'
    end as push_permission
  , case
      when max(mail_permission) = 1 then '許諾あり'
      else '許諾なし'
    end as mail_permission
from
  merged
left join
  email_mst using (customer_id)
group by
  1,13,14