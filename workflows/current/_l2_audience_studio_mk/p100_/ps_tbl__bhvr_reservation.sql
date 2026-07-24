select
  customer_id as mstr__id
  , id as hst_reservation_id
  , td_date_trunc('day', td_time_parse(start_time, 'jst'), 'jst') as reserve_date_datetime
  , td_time_parse(start_time, 'jst') as reserve_timeslot_start_datetime
  , td_time_parse(end_time, 'jst') as reserve_timeslot_end_datetime
  , case day_of_week(date(substr(start_time, 1, 10)))
      when 1 then '月曜日'
      when 2 then '火曜日'
      when 3 then '水曜日'
      when 4 then '木曜日'
      when 5 then '金曜日'
      when 6 then '土曜日'
      when 7 then '日曜日'
    end as reserve_dow
  , reserved_from
  , shop_name as reserve_shop
  , product_name as reserve_product
  , case status
      when 0 then '0.キャンセル'
      when 1 then '1.予約中'
      when 2 then '2.施術開始'
      when 3 then '3.施術終了'
    end as reservation_status
from
  _l1_mysql_reservation.reservations
  left join (select id as reservation_person_id, member_card_no from _l1_mysql_reservation.reservation_persons) using (reservation_person_id)
  left join (select id as customer_id, members_card_no as member_card_no from _l1_mysql_pos.customers) using (member_card_no)
  left join (select reservation_id as id, resource_timetable_id from _l1_mysql_reservation.reservation_relations) using (id)
  left join (select id as resource_timetable_id, mst_shop_id as property_id from _l1_mysql_reservation.resource_timetables) using (resource_timetable_id)
  left join (select property_id, shop_no, shop_name from _integration_datamart.mst_shop) using (property_id)
  left join (select id as mst_product_id, name as product_name from _l1_mysql_pos.mst_products) using (mst_product_id)
where
  coalesce(deleted, 0) = 0