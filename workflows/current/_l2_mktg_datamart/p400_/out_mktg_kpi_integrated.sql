with kpi_app_session as (
  select
    yow
    , woy
    , r_week
    , f
    , sum(app_session) as app_session
    , sum(app_session_uu) as app_session_uu
    , sum(reservation_complete_uu) as reservation_complete_uu
  from
    _integration_datamart.z_tmp_kpi_app_session
  group by
    1,2,3,4
)

, merged_segment as (
  select
    yow
    , woy
    , processing_date
    , case
        when r_week in ('01_新規(非会員)', '02_新規(会員)') then '新規'
        else '09_既存'
      end as r_week
    , case
        when r_week in ('01_新規(非会員)', '02_新規(会員)') then '新規'
        else '既存'
      end as f
    , sum(customer_uu) as customer_uu
    , sum(reservation_complete_uu) as reservation_complete_uu
    , sum(order_customer_uu) as order_customer_uu
    , sum(order_count) as order_count
    , sum(option_order_count) as option_order_count
    , sum(nomination_order_count) as nomination_order_count
    , sum(treatment_minutes) as treatment_minutes
    , sum(app_session) as app_session
    , sum(app_session_uu) as app_session_uu
  from
    kpi_app_session
  inner join
    _integration_datamart.z_tmp_kpi_rf using (yow, woy, r_week, f)
  group by
    1,2,3,4,5
)

, merged_original_segment as (
  select
    yow
    , woy
    , processing_date
    , r_week
    , f
    , customer_uu
    , reservation_complete_uu
    , order_customer_uu
    , order_count
    , option_order_count
    , nomination_order_count
    , treatment_minutes
    , app_session
    , app_session_uu
  from
    kpi_app_session
  inner join
    _integration_datamart.z_tmp_kpi_rf using (yow, woy, r_week, f)
)


select
  yow as "年"
  , woy as "週数"
  , processing_date as "営業日の週"
  , r_week as "R/w"
  , f as "F"
  , customer_uu as "セグメント顧客数"
  , reservation_complete_uu as "予約完了UU数（CV）"
  , order_customer_uu as "施術顧客数"
  , order_count as "施術件数"
  , option_order_count as "オプション施術件数"
  , nomination_order_count as "指名施術件数"
  , treatment_minutes as "合計施術分数"
  , app_session as "APP セッション数"
  , app_session_uu as "APP セッションUU数"
from (
  select * from merged_segment where r_week <> '新規'
   union all
  select * from merged_original_segment
)
order by
  1,2,3,4,5