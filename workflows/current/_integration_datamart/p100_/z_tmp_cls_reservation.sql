with prep_reservation_order as (
  select distinct
    reservation_id
    , order_id
    , customer_id
  from
    _integration_datamart.cls_order_detail
  where
    reservation_id is not null
)
, prep_customer_first_order as (
  select
    customer_id
    , min(time) as first_order_unixtime
  from
    _integration_datamart.cls_order_detail
  where
    customer_id is not null
  group by
    customer_id
)
, prep_reservation as (
  select
    id as reservation_id
    , customer_id
    , phone_no
    , email
    , shop_no
    , reservation_code
    , reserved_from
    , status
    , case status
        when 0 then '0.キャンセル'
        when 1 then '1.予約中'
        when 2 then '2.施術開始'
        when 3 then '3.施術終了'
      end as reservation_status
    , parent_reservation_id
    , reservation_index
    , td_time_parse(created, 'jst') as created_unixtime
    , td_time_parse(start_time, 'jst') as start_unixtime
  from
    _l1_mysql_reservation.reservations
    left join (select id as reservation_person_id, member_card_no, phone as phone_no, email from _l1_mysql_reservation.reservation_persons) using (reservation_person_id)
    left join (select id as customer_id, members_card_no as member_card_no from _l1_mysql_pos.customers
inner join (select members_card_no, max(modified) as modified from _l1_mysql_pos.customers where coalesce(deleted, 0) = 0 group by 1) using (members_card_no, modified)
where coalesce(deleted, 0) = 0) using (member_card_no)
    left join (select reservation_id as id, resource_timetable_id from _l1_mysql_reservation.reservation_relations) using (id)
    left join (select id as resource_timetable_id, mst_shop_id as property_id from _l1_mysql_reservation.resource_timetables) using (resource_timetable_id)
    left join (select property_id, shop_no from _integration_datamart.mst_shop) using (property_id)
)

select distinct
  td_date_trunc('week', t0.created_unixtime, 'jst') as time
  , td_time_string(td_date_trunc('week', t0.created_unixtime, 'jst'), 'd!', 'jst') as week
  , t0.created_unixtime
  , t0.reservation_id
  , t0.start_unixtime
  , t0.parent_reservation_id
  , t0.status
  , t0.reserved_from
  , coalesce(t0.customer_id, t1.customer_id) as customer_id
  , t0.phone_no
  , t0.email
  , case
      when coalesce(t0.customer_id, t1.customer_id) is null then 'ゲスト'
      when td_date_trunc('week', t0.created_unixtime, 'jst') <= td_date_trunc('week', coalesce(t2.first_order_unixtime, td_scheduled_time()), 'jst') then '新規'
      when td_date_trunc('week', t0.created_unixtime, 'jst') > td_date_trunc('week', coalesce(t2.first_order_unixtime, td_scheduled_time()), 'jst') then '既存'
    end as new_repeat
  , first_value(shop_no) over (partition by coalesce(t0.customer_id, t1.customer_id, t0.reservation_id) order by t0.created_unixtime) as shop_no
from
  prep_reservation as t0
  left join prep_reservation_order as t1 on t0.reservation_id = t1.reservation_id
  left join prep_customer_first_order as t2 on coalesce(t0.customer_id, t1.customer_id) = t2.customer_id