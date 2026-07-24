select
  customer_id as mstr__id
  , order_id
  , td_time_parse(business_date, 'jst') as order_date_datetime
  , day_of_week(date(business_date)) as order_dow
  , start_time as order_timeslot_start_datetime
  , end_time as order_timeslot_end_datetime
  , max(treatment_minutes) as treatment_minutes
  , max(uriage1) as order_amount_price
  , case
      when nomination_fee = 0.0 then '指名なし'
      when nomination_fee < 182.0 then '性別指名'
      when nomination_fee >= 182.0 then 'TP指名'
    end as nomination_type
  , therapist_id
  , shop_name as order_shop_name
  , shop_area
  , shop_prefecture
  , array_join(array_sort(array_distinct(array_agg(product_name))), ',') as order_product
from
  _integration_datamart.cls_order_detail
left join
  (select property_id, shop_name, area_name as shop_area, pref_name as shop_prefecture from _integration_datamart.mst_shop) using (property_id)
group by
  1,2,3,4,5,6,9,10,11,12,13