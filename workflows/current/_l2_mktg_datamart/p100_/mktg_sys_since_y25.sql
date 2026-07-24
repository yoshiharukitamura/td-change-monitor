with customer_rf_shop as (
  select distinct
    time
    , customer_id
    , first_order_unixtime
    , r_week
    , shop_no_last_order
  from
    _integration_datamart.hst_weekly_customer_rf
    inner join (select time, customer_id from _integration_datamart.z_tmp_cls_reservation) using (time, customer_id)    
  where
    time >= td_date_trunc('week', td_time_parse('2025-01-01', 'jst'), 'jst')
)

select
  week
  , reserved_from
  , case
      when customer_id is null then 'ゲスト'
      when td_time_parse(week, 'jst') <= td_date_trunc('week', coalesce(first_order_unixtime, td_scheduled_time()), 'jst') then '新規'
      when td_time_parse(week, 'jst') > td_date_trunc('week', coalesce(first_order_unixtime, td_scheduled_time()), 'jst') then '既存'
      else '例外'
    end as new_repeat
  , case
      when r_week between 0 and 12 then 'R/w0-12'
      when r_week between 13 and 24 then 'R/w13-24'
      when r_week >= 25 then 'R/w25-'
      else 'null'
    end as r
  , shop_no_last_order as shop_no
  , count(distinct if(parent_reservation_id is null, reservation_id, null)) as reservation_count
  , count(distinct reservation_id) as order_reservation_count
  , count(distinct if(status in (1, 2, 3), reservation_id, null)) as fullfill_reservation_count
  , count(distinct if(status in (0), reservation_id, null)) as cancel_count
from
  _integration_datamart.z_tmp_cls_reservation
  left join customer_rf_shop using (time, customer_id)
where
  time >= td_date_trunc('week', td_time_parse('2025-01-01', 'jst'), 'jst')
group by
  1,2,3,4,5
order by
  1 desc,2,3,4