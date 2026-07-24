with week_list as (
  select
    distinct
    processing_date
  from
    _integration_datamart.hst_weekly_customer_rf_w12f
  where 
    time >= td_time_parse('2023-10-01', 'jst')
)

, weekly_customer_status as (
  select
    distinct
    processing_date
    , customer_id
    , r_week
    , f
    , first_order_unixtime
    , nomination_last_order
    , shop_no_last_order
    , shop_name as shop_name_last_order
  from
    _integration_datamart.hst_weekly_customer_rf_w12f as t0
  left join 
    _integration_datamart.mst_shop as t1
    on cast(t0.shop_no_last_order as varchar) = t1.shop_no
  where
    t0.time between td_time_parse('2023-10-01', 'jst') and td_date_trunc('week', td_scheduled_time(), 'jst')
)

, app_not_order_customer as (
  select
    td_time_string(week, 'd!', 'jst') as processing_date
    , count(if(first_res_week is null or first_res_week > week, 1)) as app__not_order_customer_count
    , count(if(nonmember_history_flag = 0 and first_res_week is null or first_res_week > week, 1)) as app__new__not_order_customer_count
    , count(if(nonmember_history_flag = 1 and first_res_week is null or first_res_week > week, 1)) as app__exist__not_order_customer_count
  from (
    select
      week
      , user_pseudo_id
      , nonmember_history_flag
      , min(if(customer_id is not null, week)) over (partition by user_pseudo_id) as first_res_week
    from (
      select
        td_date_trunc('week', time, 'jst') as week,
        user_pseudo_id,
        max(customer_id) as customer_id
      from _integration_datamart.z_tmp_cls_app_log_104w
      group by 1,2
    )
    left join _integration_datamart.z_tmp_kpi_rf_base using (customer_id)
  )
  group by 1
)

, order_log as (
  select
    customer_id
    , count(distinct order_id) as order_count
    , min(business_date) as first_order_date
    , max(business_date) as last_order_date
  from
    _integration_datamart.cls_order_detail
  group by 1
)

, prep_web_not_order_customer as (
 select
   distinct
   dtb_customer_id as cutomer_id
   , created_app
   , email
   , phone_no
   , last_login_app
   , is_login_app
   , substr(created, 1, 10) as created
   , order_count
   , first_order_date
   , last_order_date
 from
   _l1_mysql_hp.customers as t0
  left join
    order_log as t1
    on t0.dtb_customer_id = t1.customer_id
)


, web_not_order_customer as (
  select
    td_time_string(td_date_trunc('week', td_time_parse(created, 'jst'), 'jst'), 'd!', 'jst') as processing_date
    , count(if(first_order_date is null, 1)) as web__new__customer_count
    , count(if(created > first_order_date, 1)) as web__exist__customer_count
  from
    prep_web_not_order_customer
  where
    created_app is null
    and created >= '2026-06-23'
  group by 1
)

, web__exist__customer_count as (
  select
    td_time_string(td_date_trunc('week', td_time_parse(created, 'jst'), 'jst'), 'd!', 'jst') as processing_date
    , count(distinct dtb_customer_id) as web__exist__customer_count
  from
    _l1_mysql_hp.customers as t0
    left join 
      _integration_datamart.z_tmp_kpi_rf_base as t1
      on t0.dtb_customer_id = t1.customer_id
         and td_time_string(td_date_trunc('week', td_time_parse(t0.created, 'jst'), 'jst'), 'd!', 'jst') = t1.processing_date
  where
    created_app is null
    and substr(created, 1, 10) >= '2026-06-23'
    and nonmember_history_flag = 1
  group by 1
)

, agg as (
  select
    processing_date
    , case
        when guest_flag = '非会員_新規' then '01_非会員（新規）'
        when guest_flag = '非会員_既存'
          and date_diff('week', date(nonmember_first_reserve_week), date(processing_date)) between 1 and 12 then '02_非会員_新規（オンボーディング）'
        when guest_flag = '非会員_既存' then '03_非会員（既存）'
        when guest_flag = '非会員_不明' then '04_非会員（不明）'

        when r_week is null and customer_id is not null then '05_新規（当週）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) between 1 and 12 then '06_新規（オンボーディング）'

        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f = 1 then '11_既存_ライト（12wF1）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f = 2 then '12_既存_ミドル（12wF2）'
        when date_diff('week', date(td_time_string(td_date_trunc('week', first_order_unixtime, 'jst'), 'd!', 'jst')), date(processing_date)) >= 13 and
          r_week between 1 and 12 and f >= 3 then '13_既存_ヘビー（12wF3+）'
        when r_week between 13 and 52 and f = 0 then '14_疎遠（R/w13-52）'
        when r_week >= 53 and f = 0 then '15_離反（R/w53+）'
      end as segment
    /* 新規のnext_week、prev_yearが出るように加工 */
    --, coalesce(shop_no_last_order, 0) as shop_no_last_order
    --, coalesce(shop_name_last_order, '判定不可') as shop_name_last_order
    , nullif(count(distinct coalesce(cast(customer_id as varchar), person_key)), 0) as customer_count
    , nullif(count(distinct if(order_count >= 1, coalesce(cast(customer_id as varchar), person_key))), 0) as order_customer_count
    , sum(order_count) as order_count
    , sum(treatment_minutes) as treatment_minutes
    , sum(if(nomination_flag = 1, order_count, 0)) as nomination_order_count
    , sum(if(nomination_flag = 1 and nomination_tp_flag = 1, order_count, 0)) as nomination_tp_order_count
    , sum(if(nomination_flag = 1 and nomination_gender_flag = 1, order_count, 0)) as nomination_gender_order_count

    , sum(if(standard_flag = 1, order_count, 0)) as set_order_count
    , sum(if(foot_flag = 1, order_count, 0)) as set_foot_order_count
    , sum(if(addon_flag = 1, order_count, 0)) as set_other_order_count

    , sum(if(op_flag = 1, order_count, 0)) as option_order_count
    , sum(if(op_pmat_flag = 1, order_count, 0)) as option_pmatt_order_count
    , sum(if(op_other_flag = 1, order_count, 0)) as option_other_order_count
  from weekly_customer_status
  full join _integration_datamart.z_tmp_kpi_rf_base using (processing_date, customer_id)
  group by 1,2
)

, agg__app_web as (
  select
    processing_date
    , case
        when guest_flag = '非会員_新規' then '01_非会員（新規）'
        when guest_flag = '非会員_既存'
          and date_diff('week', date(nonmember_first_reserve_week), date(processing_date)) between 1 and 12 then '02_非会員_新規（オンボーディング）'
        when guest_flag = '非会員_既存' then '03_非会員（既存）'
        when guest_flag = '非会員_不明' then '04_非会員（不明）'
        when r_week is null and customer_id is not null and (member_type = 'APP会員' or member_type is null) and nonmember_history_flag = 0 then '07_APP会員（新規）'
        when r_week is null and customer_id is not null and (member_type = 'APP会員' or member_type is null) and nonmember_history_flag = 1 then '08_APP会員（既存）'
        when r_week is null and customer_id is not null and member_type = 'WEB会員' and nonmember_history_flag = 0 then '09_WEB会員（新規）'
        when r_week is null and customer_id is not null and member_type = 'WEB会員' and nonmember_history_flag = 1 then '10_WEB会員（既存）'
        else 'その他'
      end as segment
    /* 新規のnext_week、prev_yearが出るように加工 */
    --, coalesce(shop_no_last_order, 0) as shop_no_last_order
    --, coalesce(shop_name_last_order, '判定不可') as shop_name_last_order
    , nullif(count(distinct coalesce(cast(customer_id as varchar), person_key)), 0) as customer_count
    , nullif(count(distinct if(order_count >= 1, coalesce(cast(customer_id as varchar), person_key))), 0) as order_customer_count
    , sum(order_count) as order_count
    , sum(treatment_minutes) as treatment_minutes
    , sum(if(nomination_flag = 1, order_count, 0)) as nomination_order_count
    , sum(if(nomination_flag = 1 and nomination_tp_flag = 1, order_count, 0)) as nomination_tp_order_count
    , sum(if(nomination_flag = 1 and nomination_gender_flag = 1, order_count, 0)) as nomination_gender_order_count

    , sum(if(standard_flag = 1, order_count, 0)) as set_order_count
    , sum(if(foot_flag = 1, order_count, 0)) as set_foot_order_count
    , sum(if(addon_flag = 1, order_count, 0)) as set_other_order_count

    , sum(if(op_flag = 1, order_count, 0)) as option_order_count
    , sum(if(op_pmat_flag = 1, order_count, 0)) as option_pmatt_order_count
    , sum(if(op_other_flag = 1, order_count, 0)) as option_other_order_count
  from weekly_customer_status
  full join _integration_datamart.z_tmp_kpi_rf_base using (processing_date, customer_id)
  group by 1,2
)

, agg__fixed as (
  select * from agg
   union all
  select * from agg__app_web where segment in ('07_APP会員（新規）', '08_APP会員（既存）', '09_WEB会員（新規）', '10_WEB会員（既存）')
)

select
  year_of_week(date(processing_date)) as yow
  , week_of_year(date(processing_date)) as woy
  , processing_date
  , segment
  --, shop_no_last_order
  --, shop_name_last_order
  , coalesce(customer_count, 0) as customer_uu
  , coalesce(order_customer_count, 0) as order_customer_uu
  , 1.0 * coalesce(order_customer_count, 0) / sum(coalesce(order_customer_count, 0)) over (partition by processing_date) as order_customer_uu_rate
  , coalesce(order_count, 0) as order_count
  , coalesce(treatment_minutes, 0) as treatment_minutes
  , coalesce(nomination_order_count, 0) as nomination_order_count
  , coalesce(nomination_tp_order_count, 0) as nomination_tp_order_count
  , coalesce(nomination_gender_order_count, 0) as nomination_gender_order_count
  , coalesce(set_order_count, 0) as set_order_count
  , coalesce(set_foot_order_count, 0) as set_foot_order_count
  , coalesce(set_other_order_count, 0) as set_other_order_count
  , coalesce(option_order_count, 0) as option_order_count
  , coalesce(option_pmatt_order_count, 0) as option_pmatt_order_count
  , coalesce(option_other_order_count, 0) as option_other_order_count
from week_list
left join agg__fixed using(processing_date)
left join app_not_order_customer using(processing_date)
left join web_not_order_customer using (processing_date)
where year_of_week(date(processing_date)) >= 2024
order by
  1,2,3,4