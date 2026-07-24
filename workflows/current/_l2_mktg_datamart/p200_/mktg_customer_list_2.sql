--前週未予約のAPP Rw/13以上の顧客リスト
with map_ids as (
  select
    coalesce(t1.user_pseudo_id, t2.user_pseudo_id) as user_pseudo_id
    , coalesce(t1.customer_id, t2.customer_id) as customer_id_fixed
  from (
    select
      user_pseudo_id
      , max_by(customer_id, event_unixtime) as customer_id
    from _integration_datamart.z_tmp_cls_app_log_104w
    where
      td_date_trunc('week', event_unixtime, 'jst') = td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-7d', 'jst')
      and customer_id is not null
    group by user_pseudo_id
  ) as t1
  full join (
    select
      user_pseudo_id
      , max_by(customer_id, event_unixtime) as customer_id
    from _integration_datamart.z_tmp_cls_app_reserve
    inner join (
      select reservation_id, customer_id
      from _integration_datamart.z_tmp_cls_reservation
      where reserved_from = 'APP' and parent_reservation_id is null
    ) using (reservation_id)
    where
      td_date_trunc('week', event_unixtime, 'jst') = td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-7d', 'jst')
      and customer_id is not null
    group by user_pseudo_id
  ) as t2 on t1.user_pseudo_id = t2.user_pseudo_id
)


select
  customer_id_fixed as customer_id
  , coalesce(if(pos.deleted = 1 and hp.deleted = 0, 1, 0), null) as deactivated_flg
  , coalesce(if(hp.created_app is not null, 1, 0), null) as app_single_flg
  , coalesce(if(hp.mailflg = 1 and pos.mail_magazine = 3, 1, 0), null) as mail_flg
  , coalesce(hp.push_noti, null) as push_flg
from
  _integration_datamart.z_tmp_cls_app_log_104w
  left join map_ids using (user_pseudo_id)
  left join (
    select
      customer_id as customer_id_fixed
      , r_week
    from hst_weekly_customer_rf
    where
      time = td_date_trunc('day', td_scheduled_time(), 'jst')
    group by 1,2
  ) using (customer_id_fixed)

  -- l0_hp.customers の最新レコード
  left join (
    select 
      dtb_customer_id as customer_id_fixed,
      push_noti,
      activated,
      mailflg,
      deleted,
      created_app
    from _l0_mysql_hp.customers
    inner join (
      select dtb_customer_id, max(time) as time
      from _l0_mysql_hp.customers
      group by dtb_customer_id
    ) using (dtb_customer_id, time)
    where created_app is not null
  ) as hp using(customer_id_fixed)

  -- l0_pos.customers の最新レコード
  left join (
    select
      id as customer_id_fixed,
      mail_magazine,
      deleted
    from _l0_mysql_pos.customers
    inner join (
      select id, max(time) as time
      from _l0_mysql_pos.customers
      group by id
    ) using (id, time)
  ) as pos using(customer_id_fixed)

  -- 社用アカウントなどを除外
  inner join (select distinct id as customer_id_fixed from _l1_mysql_pos.customers) using (customer_id_fixed)

where
  td_date_trunc('week', event_unixtime, 'jst') = td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-7d', 'jst')
  and customer_id_fixed is not null
  and r_week >= 13
  and event_status between 1 and 4
group by 
  1,2,3,4,5
having 
  max(event_status) <= 3