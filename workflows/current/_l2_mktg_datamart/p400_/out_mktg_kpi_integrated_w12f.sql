select
  yow as "年"
  , woy as "週数"
  , segment as "セグメント"
  , customer_uu as "セグメント顧客数"
  , coalesce(reservation_complete_uu, 0) as "予約完了UU数（CV）"
  , order_customer_uu as "施術顧客数"
  , order_count as "施術件数"
  , 1.0 * treatment_minutes / order_count as "平均施術分数"
  , nomination_order_count as "指名施術数"
  , nomination_tp_order_count as "指名_TP_施術数"
  , nomination_gender_order_count as "指名_性別_施術数"
  , set_order_count as "セット_施術数"
  , set_foot_order_count as "セット_足つぼ_施術数"
  , set_other_order_count as "セット_その他_施術数"
  , option_order_count as "OP_施術数"
  , option_pmatt_order_count as "OP_Pマット_施術数"
  , option_other_order_count as "OP_その他_施術数"
  , 1.0 * nomination_order_count / order_count as "指名率"
  , coalesce(app_session, 0) as "APPセッション数"
  , coalesce(app_session_uu, 0) as "APPセッションUU数"
  , coalesce(1.0 * reservation_complete_uu / nullif(app_session_uu, 0), 0) as "APP CVR"
from
  _integration_datamart.z_tmp_kpi_rf_result
left join
  _integration_datamart.z_tmp_kpi_app_session_w12f
using (yow, woy, segment)
order by
  yow, woy, segment