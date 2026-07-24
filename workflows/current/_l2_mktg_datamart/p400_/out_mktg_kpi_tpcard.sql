select
  business_week as "営業日の週"
  , reservation_count as "予約数"
  , session_count as "APPビュー数"
  /* app */
  , app_reservation_count as "APP経由_予約数"
  , app_order_count as "APP経由_施術数"
  , app_nomination_count as "APP経由_指名数"
  , app_first_nomination as "APP経由_初指名"
  , app_first_nomination_tpcard as "APP経由_初指名_TPカード経由"
  , app_first_order_first_nomination_tpcard as "APP経由_初施術-初指名_TPカード経由"
  , app_second_order_first_nomination_tpcard as "APP経由_2回目施術-初指名_TPカード経由"
  , app_third_or_more_order_first_nomination_tpcard as "APP経由_3回目施術-初指名_TPカード経由"
  , app_first_nomination_non_tpcard as "APP経由_初指名_TPカード非経由"
  , app_first_order_first_nomination_non_tpcard as "APP経由_初施術-初指名_TPカード非経由"
  , app_second_order_first_nomination_non_tpcard as "APP経由_2回目施術-初指名_TPカード非経由"
  , app_third_or_more_order_first_nomination_non_tpcard as "APP経由_3回目施術-初指名_TPカード非経由"

  , app_repeat_nomination as "APP経由_リピート指名"
  , app_repeat_nomination_tpcard as "APP経由_リピート指名_TPカード経由"
  , app_repeat_nomination_non_tpcard as "APP経由_リピート指名_TPカード非経由"

  , app_free as "APP経由_フリー"
  , app_free_tpcard as "APP経由_フリー_TPカード経由"
  , app_free_first_order_tpcard as "APP経由_フリー_初施術_TPカード経由"
  , app_free_second_or_more_order_tpcard as "APP経由_フリー_2回目以上_TPカード経由"
  , app_free_non_tpcard as "APP経由_フリー_TPカード非経由"
  , app_free_first_order_non_tpcard as "APP経由_フリー_初施術_TPカード非経由"
  , app_free_second_or_more_order_non_tpcard as "APP経由_フリー_2回目以上_TPカード非経由"

  , app_cancel as "APP経由_キャンセル"
  , app_cancel_tpcard as "APP経由_キャンセル_TPカード経由"
  , app_cancel_non_tpcard as "APP経由_キャンセル_TPカード非経由"

  , app_out as "APP経由_離脱数"
  , app_out_via_tpcard as "APP経由_離脱数_TPカード経由"
  , app_out_non_tpcard as "APP経由_離脱数_TPカード非経由"

  , other_reservation_count as "APPビューあり_その他経由_予約"
  , other_order_count as "APPビューあり_その他経由_施術数"
  , other_nomination_count as "APPビューあり_その他経由_指名数"
  , other_first_nomination as "APPビューあり_その他経由_初指名"
  , other_first_nomination_tpcard as "APPビューあり_その他経由_初指名_TPカード経由"
  , other_first_order_first_nomination_tpcard as "APPビューあり_その他経由_初施術-初指名_TPカード経由"
  , other_second_order_first_nomination_tpcard as "APPビューあり_その他経由_2回目施術-初指名_TPカード経由"
  , other_third_or_more_order_first_nomination_tpcard as "APPビューあり_その他経由_3回目施術-初指名_TPカード経由"
  , other_first_nomination_non_tpcard as "APPビューあり_その他経由_初指名_TPカード非経由"

  , other_repeat_nomination as "APPビューあり_その他経由_リピート指名"
  , other_repeat_nomination_tpcard as "APPビューあり_その他経由_リピート指名_TPカード経由"
  , other_repeat_nomination_non_tpcard as "APPビューあり_その他経由_リピート指名_TPカード非経由"

  , other_free as "APPビューあり_その他経由_フリー"
  , other_free_tpcard as "APPビューあり_その他経由_フリー_TPカード経由"
  , other_free_non_tpcard as "APPビューあり_その他経由_フリー_TPカード非経由"

  , other_cancel as "APPビューあり_その他経由_キャンセル"

  , no_app_view_reservation as "APPビューなし_予約数"
  , no_app_view_other_reservation as "APPビューなし_その他経由_予約"
  --, no_app_view_app_reservation as "APPビューなし_APP経由_施術数"
  , no_app_view_other_order as "APPビューなし_その他経由_施術数"
  , no_app_view_other_nomination as "APPビューなし_その他経由_指名数"
  , no_app_view_other_first_nomination as "APPビューなし_その他経由_初指名"
  , no_app_view_other_first_order_first_nomination as "APPビューなし_その他経由_初施術-初指名"
  , no_app_view_other_second_order_first_nomination as "APPビューなし_その他経由_2回目施術-初指名"
  , no_app_view_other_third_or_more_order_first_nomination as "APPビューなし_その他経由_3回目施術-初指名"
  , no_app_view_repeat_nomination as "APPビューなし_リピート指名"
  , no_app_view_repeat_nomination_non_tpcard as "APPビューなし_リピート指名_TPカード非経由"
  , no_app_view_free as "APPビューなし_フリー"
  , no_app_view_free_non_tpcard as "APPビューなし_フリー_TPカード非経由"
  , no_app_view_free_first_order_non_tpcard as "APPビューなし_フリー_初施術_TPカード非経由"
  , no_app_view_free_second_or_more_order_non_tpcard as "APPビューなし_フリー_2回目以上_TPカード非経由"
  , no_app_view_other_cancel as "APPビューなし_その他経由_キャンセル数"

  /* no reservation */
  , no_reservation_order as "予約なし施術数"
from
  l2_verification.tmp_kpi__tp_card
order by
  1