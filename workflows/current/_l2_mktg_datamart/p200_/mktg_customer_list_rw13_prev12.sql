with week_list as (
  select
    distinct
    processing_date
  from 
    _integration_datamart.hst_weekly_customer_rf
)

, rw_customer as (
  select
    processing_date
    , customer_id
    , r_week
    , f
    , shop_no_last_order
    , shop_name as shop_name_last_order
  from
    hst_weekly_customer_rf as t0
  left join 
    mst_shop as t1
    on cast(t0.shop_no_last_order as varchar) = t1.shop_no
)

, merged as (
  select
    processing_date
    , customer_id
    , r_week
    , lag(r_week, 1) over (partition by customer_id order by processing_date) as r_week_prev_w
    , case
        when f between 1 and 5 then 'F1-5'
        when f >= 6 then 'F6-'
      end as f
    , shop_no_last_order
    , shop_name_last_order
  from 
    week_list
  left join
    rw_customer using (processing_date)
)

select
  processing_date
  , customer_id
  , f
  , shop_name_last_order
  , coalesce(if(hp.created_app is not null, 1, 0), null) as app_single_flg
  , coalesce(if(pos.deleted = 1 and hp.deleted = 0, 1, 0), null) as deactivated_flg
  , coalesce(if(hp.mailflg = 1 and pos.mail_magazine = 3, 1, 0), null) as mail_flg
  -- , coalesce(hp.push_noti, null) as push_flg
from 
  merged
left join (
    select 
      dtb_customer_id as customer_id
      -- , push_noti
      , activated
      , mailflg
      , deleted
      , created_app
    from _l0_mysql_hp.customers
    inner join (
      select dtb_customer_id, max(time) as time
      from _l0_mysql_hp.customers
      group by dtb_customer_id
    ) using (dtb_customer_id, time)
    where created_app is not null
  ) as hp using(customer_id)

left join (
  -- l0_pos.customers の最新レコード
    select
      id as customer_id
      , mail_magazine
      , deleted
    from _l0_mysql_pos.customers
    inner join (
      select id, max(time) as time
      from _l0_mysql_pos.customers
      group by id
    ) using (id, time)
  ) as pos using(customer_id)

  -- 社用アカウントなどを除外
  inner join (
    select distinct id as customer_id 
    from 
      _l1_mysql_pos.customers) using (customer_id)
where
  processing_date = td_time_string(td_date_trunc('week', td_scheduled_time(), 'jst'), 'd!', 'jst')
  and r_week = 13
  and r_week_prev_w = 12
order by
  customer_id