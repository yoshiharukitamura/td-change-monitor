with customer_list as (
  select distinct
    customer_id
    , segment
    , td_time_parse('${segment.before_from}', 'jst') as before_from
    , td_time_parse('${segment.before_to}', 'jst') as before_to
    , td_time_parse('${segment.after_from}', 'jst') as after_from
    , least(td_time_parse('${segment.after_to}', 'jst'), ${moment(session_date).subtract(1, 'day').unix()}) as after_to
  from
    ${td.database}.list_demand_customers
  where
    list_name = '${segment.name}'
)
, prep_orders as (
  select
    segment
    , order_id
    , td_time_parse(business_date, 'jst') as business_date
    , case
        when td_time_parse(business_date, 'jst') between before_from and before_to
          then '実施前:'||td_time_format(before_from, 'MMdd', 'jst')||'~'||td_time_format(before_to, 'MMdd', 'jst')
        when td_time_parse(business_date, 'jst') between after_from and after_to
          then '実施中:'||td_time_format(after_from, 'MMdd', 'jst')||'~'||td_time_format(after_to, 'MMdd', 'jst')
      end as span
    , if(dow(cast(business_date as date)) in (6, 7) or coalesce(hldy, 0) = 1, '土日祝', '平日') as dow_type
    , property_id
    , customer_id
    , sum(if(order_detail_id_seq = 1, treatment_minutes_in_hour)) as treatment_minutes
    , sum(if(order_id_hour_seq = 1, uriage1)) as sales_amount
  from
    _integration_datamart.cls_order_detail
    inner join customer_list using (customer_id)
    left join (select substr(target_date, 1, 10) as business_date, 1 as hldy from _l1_mysql_pos.mst_holidays) using (business_date)
  where business_date not in ('2025-09-10')
  group by
    1,2,3,4,5,6,7
)

select
  segment as "施策対象"
  , target_uu as "対象人数"
  , span as "期間"
  , type as "平日/土日祝"
  , sum(sales_amount)/1000 as "売上高1(千円)"
  , count(distinct if(treatment_minutes>0, order_id, null)) as "施術件数(件)"
  , sum(treatment_minutes)/60 as "施術時間(h)"
  , sum(treatment_minutes)/cast(count(distinct if(treatment_minutes>0, order_id, null)) as double) as "施術分数(分)"
  , sum(sales_amount)/cast(count(distinct if(treatment_minutes>0, order_id, null)) as double) as "施術単価(円)"
from (
    select *, '全日' as type from prep_orders
    union all select *, dow_type as type from prep_orders
  )
  left join (select segment, count(distinct customer_id) as target_uu from customer_list group by segment) using (segment)
where
  span is not null
group by
  1,2,3,4
order by
  1,2,3,4