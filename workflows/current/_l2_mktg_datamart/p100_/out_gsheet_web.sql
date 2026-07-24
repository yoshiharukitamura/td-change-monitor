select
  business_week as "営業日の週"
  , traffic_source as "流入経路"
  , new_repeat as "新規既存"
  , r as "R"
  , sum(session_count) as "セッション数"
  , sum(session_uu) as "セッションUU数"
  , sum(reservation_bahavior_uu) as "予約行動UU数"
  , sum(reservation_confirm_uu) as "予約確認UU数"
  , sum(reservation_complete_uu) as "予約完了UU数"
  , sum(reservation_order_count) as "予約施術数"
from
  tmp_mktg_web
group by
  1,2,3,4
order by
  1,2,3,4
