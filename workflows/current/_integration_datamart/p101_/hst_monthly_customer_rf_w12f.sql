with month_axis as (
  select
    td_time_parse(cast(d as varchar), 'jst') as ymd_unixtime
  from unnest(
    sequence(
      cast(date_trunc('month', cast('2024-01-01' as timestamp)) as date),
      cast(date_trunc('month', cast('2026-12-31' as timestamp)) as date),
      interval '1' month
    )
  ) as t(d)
)

select
  ma.ymd_unixtime as time
  , td_time_string(ma.ymd_unixtime, 's!', 'jst') as time_fmt
  , 'processing_date' as time_means
  , customer_id
  , ma.ymd_unixtime as processing_unixtime
  , td_time_string(ma.ymd_unixtime, 'd!', 'jst') as processing_date
  , td_time_string(ma.ymd_unixtime, 'M!', 'jst') as month
  , min(if(td_date_trunc('month', time, 'jst') < ma.ymd_unixtime, time, null)) as first_order_unixtime
  , date_diff('month', date_trunc('month', from_unixtime(max(time))), date_trunc('month', from_unixtime(ma.ymd_unixtime))) as r_month
  , cast(ceiling(date_diff('day', from_unixtime(max(time)), from_unixtime(ma.ymd_unixtime))/7.0) as int) as r_week
  , count(distinct if(time between ma.ymd_unixtime - 60*60*24*84 and ma.ymd_unixtime - 1, business_date, null)) as f
  , sum(if(order_id_hour_seq = 1 and time between ma.ymd_unixtime - 60*60*24*84 and ma.ymd_unixtime - 1, uriage1)) as sales_amount
  , sum(if(order_id_hour_seq = 1 and time between ma.ymd_unixtime - 60*60*24*84 and ma.ymd_unixtime - 1, treatment_minutes_in_hour)) as treatment_minutes
  , if(max_by(nomination_fee, order_id) > 0, 1, 0) as nomination_last_order
  , max_by(shop_no, order_id) as shop_no_last_order
from
  _integration_datamart.cls_order_detail
  cross join month_axis ma
  left join (
    select property_id, cast(shop_no as bigint) as shop_no
    from _integration_datamart.mst_shop
  ) using (property_id)
where
  customer_id is not null
  and td_date_trunc('month', time, 'jst') < ma.ymd_unixtime
group by
  customer_id
  , ma.ymd_unixtime