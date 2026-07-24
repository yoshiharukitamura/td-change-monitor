with weekly_customer_status as (
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

, agg as (
  select
    processing_date
    , customer_id
    , provisional_person_id
    , person_key
    , first_reserve_week
    , nonmember_first_reserve_week
    , order_id
    , member_type
    , member_created_week
    , guest_flag
    , nonmember_history_flag
    , member_reserve_first_flag
    , f
    , r_week
    , td_time_string(time, 'd!', 'jst') as business_date
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
  from weekly_customer_status
  full join _integration_datamart.z_tmp_kpi_rf_base using (processing_date, customer_id)
)

select
  distinct
  business_date
  , customer_id
  , order_id
  --, r_week
  --, f
  , coalesce(nonmember_history_flag, 0) as nonmember_history_flag
from
  agg
where
  td_time_parse(business_date, 'jst') = td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-1d', 'jst') 
  and segment = '05_新規（当週）'
order by
  1,2