select
  ymd_unixtime as time
  , td_time_string(ymd_unixtime, 's!', 'jst') as time_fmt
  , 'processing_date' as time_means
  , customer_id
  , ymd_unixtime as processing_unixtime
  , td_time_string(ymd_unixtime, 'd!', 'jst') as processing_date
  , td_time_string(ymd_unixtime, 'd!', 'jst') as week
  , min(if(td_date_trunc('day', time, 'jst') < ymd_unixtime, time, null)) as first_order_unixtime
  , date_diff('month', from_unixtime(max(time)), from_unixtime(ymd_unixtime)) as r_month
  , cast(ceiling(date_diff('day', from_unixtime(max(time)), from_unixtime(ymd_unixtime))/7.0) as int) as r_week
  , count(distinct if(time between ymd_unixtime - 60*60*24*7*52 and ymd_unixtime - 1, business_date, null)) as f
  , sum(if(order_id_hour_seq = 1 and time between ymd_unixtime - 60*60*24*7*52 and ymd_unixtime - 1, uriage1)) as sales_amount
  , sum(if(order_id_hour_seq = 1 and time between ymd_unixtime - 60*60*24*7*52 and ymd_unixtime - 1, treatment_minutes_in_hour)) as treatment_minutes
  , if(max_by(nomination_fee, order_id) > 0, 1, 0) as nomination_last_order
  , max_by(shop_no, order_id) as shop_no_last_order
from
  _integration_datamart.cls_order_detail
  cross join unnest (
    sequence(td_time_parse('${td.each.date_from}', 'jst'), td_time_parse('${td.each.date_to}', 'jst') , 60*60*24)
  ) as t(ymd_unixtime)
  left join (select property_id, cast(shop_no as bigint) as shop_no from _integration_datamart.mst_shop) using (property_id)
where
  customer_id is not null
  and td_date_trunc('day', time, 'jst') < ymd_unixtime
group by
  customer_id
  , ymd_unixtime
