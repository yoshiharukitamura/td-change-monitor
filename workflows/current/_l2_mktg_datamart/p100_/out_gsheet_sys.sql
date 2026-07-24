select
  week
  , reserved_from
  , new_repeat as "新規既存"
  , r as "R"
  , sum(reservation_count) as "予約数"
  , sum(order_reservation_count) as "施術予約数"
  , sum(fullfill_reservation_count) as "履行数"
  , sum(cancel_count) as "キャンセル数"
from
  tmp_mktg_sys
group by
  1,2,3,4
order by
  1,2,3,4
