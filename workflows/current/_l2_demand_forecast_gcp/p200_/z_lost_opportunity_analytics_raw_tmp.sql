select
  *
  , substr('月火水木金土日', dow(cast(substr(coalesce(reservation_dt, session_start_time), 1, 10) as timestamp)), 1) as reservation_dow
  , substr(coalesce(reservation_dt, session_start_time), 12, 2) as reservation_hour
  , date_diff('day', cast(substr(reservation_dt, 1, 10) as date), cast(substr(treatment_dt, 1, 10) as date)) as date_diff_reserve_treat
  , substr(treatment_dt, 12, 2) as treatment_hour
  , if(not(is_therapy_date=1 or is_reserve_0day=1 or pv_reservation_complete>=1 or pv_reservation_change>=1) and pv_shop_detail>=1 and is_reserve_within_3day=0 and stay_sec>=10, 1, 0) as loss_opps
from (
    select
      t1.session_id
      , t1.user_pseudo_id
      , if(t1.customer_id is null, 0, 1) as is_member
      , coalesce(cast(t1.customer_id as varchar), t1.user_pseudo_id) as customerid_deviceid
      , t1.customer_id
      , min(t1.time) as time
      , td_time_string(min(t1.session_start_datetime), 's!', 'jst') as session_start_time
      , td_time_string(min(t1.session_start_date), 'd!', 'jst') as session_start_date
      , min(shop_count) as shop_count
      , array_distinct(array_agg(t1.mst_shop_no) filter(where t1.mst_shop_no is not null)) as arry_mst_shop_no
      , sum(if(event_category='01_店舗詳細', 1, 0)) as pv_shop_detail
      , sum(if(event_category='02_予約確認', 1, 0)) as pv_reservation_confirm
      , sum(if(event_category='03_予約完了', 1, 0)) as pv_reservation_complete
      , sum(if(event_category='04_予約修正完了', 1, 0)) as pv_reservation_change
      , sum(if(event_category='05_SCI', 1, 0)) as pv_sci
      , sum(if(event_category='90_お知らせ', 1, 0)) as pv_notification
      , sum(if(event_category='91_予約履歴', 1, 0)) as pv_reservation_history
      , sum(if(event_category='92_店舗検索', 1, 0)) as pv_shop_serach
      , sum(if(event_category='91_予約履歴' and t1.event_dt <= coalesce(t5.event_dt, t1.event_dt), 1, 0)) as pv_reservation_history_before_reserve
      , max(if(t2.customer_id is not null, 1, 0)) as is_therapy_date
      , max(if(t6.customer_id is not null, 1, 0)) as is_therapy_date_1ago
      , max(if(t7.customer_id is not null, 1, 0)) as is_reserve_within_1day
      , max(if(t7.customer_id is not null or t8.customer_id is not null, 1, 0)) as is_reserve_within_2day
      , max(if(t7.customer_id is not null or t8.customer_id is not null or t9.customer_id is not null, 1, 0)) as is_reserve_within_3day
      , max(if(t10.customer_id is not null, 1, 0)) as is_reserve_0day
      , td_time_string(td_date_trunc('hour', min(if(t1.reservation_id is not null, t1.time)), 'jst'), 's!', 'jst') as reservation_dt
      , td_time_string(td_date_trunc('hour', min(if(t4.reservation_id is not null, t4.time)), 'jst'), 's!', 'jst') as treatment_dt
      , sum(coalesce(td_time_parse(lead_event_dt, 'jst') - td_time_parse(t1.event_dt, 'jst'),0)) as stay_sec
    from
      l1_datamart_202210.prep_app_logs as t1
      left join (
          select distinct
            customer_id
            , therapy_date
          from
            prep_sys_reservation_logs_with_therapy_date
       ) as t2 on t1.customer_id = t2.customer_id and t1.session_start_date = t2.therapy_date
      left join (select td_date_trunc('day', time, 'jst') as session_start_date, count(distinct mst_shop_no) as shop_count from l1_datamart_202210.prep_app_logs group by 1) as t3 on t1.session_start_date = t3.session_start_date
      left join prep_sys_reservation_logs_with_therapy_date as t4 on t1.reservation_id = t4.reservation_id
      left join (select session_id, min(event_dt) as event_dt from l1_datamart_202210.prep_app_logs where event_category='03_予約完了' group by session_id) as t5 on t1.session_id = t5.session_id
      left join (
          select distinct
            customer_id
            , therapy_date_1ago
          from
            prep_sys_reservation_logs_with_therapy_date
       ) as t6 on t1.customer_id = t6.customer_id and t1.session_start_date = t6.therapy_date_1ago
      left join (
          select distinct
            customer_id
            , reserve_within_1day
          from
            prep_sys_reservation_logs_with_therapy_date
       ) as t7 on t1.customer_id = t7.customer_id and t1.session_start_date = t7.reserve_within_1day
      left join (
          select distinct
            customer_id
            , reserve_within_2day
          from
            prep_sys_reservation_logs_with_therapy_date
       ) as t8 on t1.customer_id = t8.customer_id and t1.session_start_date = t8.reserve_within_2day
      left join (
          select distinct
            customer_id
            , reserve_within_3day
          from
            prep_sys_reservation_logs_with_therapy_date
       ) as t9 on t1.customer_id = t9.customer_id and t1.session_start_date = t9.reserve_within_3day
      left join (
          select distinct
            customer_id
            , reserve_date
          from
            prep_sys_reservation_logs_with_therapy_date
       ) as t10 on t1.customer_id = t10.customer_id and t1.session_start_date = t10.reserve_date

    group by
      t1.session_id
      , t1.user_pseudo_id
      , t1.customer_id
  )
