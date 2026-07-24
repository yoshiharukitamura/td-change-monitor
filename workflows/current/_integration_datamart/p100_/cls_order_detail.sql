with cls__order as (
  select distinct
    id as order_id
    , substr(registered_business_date, 1, 10) as business_date
    , if(substr(registered_business_date, 1, 10)<'2019-10-01', 1.08, 1.1) as tax_rate
    , member_type
    , reservation_id
    , mst_shop_id as property_id
    , customer_id
    , td_time_parse(treatment_start_datetime, 'jst') as start_time
    , total_amount_of_treatment_minutes as treatment_minutes
    , if(visit_date_last_time is not null, 1, 0) as is_repeat
    , parent_order_id
    , phone_no
    , email
  from
    _l0_mysql_pos.orders
    inner join (
        select id, max(time) as time
        from _l0_mysql_pos.orders
        group by id
      ) using (id, time)
  where
    coalesce(deleted, 0) = 0
    and status = 2
    and registered_business_date is not null
)
, cls__order_detail as (
  select distinct
    id as order_detail_id
    , category_id
    , mst_product_id as product_id
    , price_type
    , sales_price
    , order_id
  from
    _l0_mysql_pos.order_details
    inner join (
        select id, max(time) as time
        from _l0_mysql_pos.order_details
        group by id
      ) using (id, time)
  where
    coalesce(deleted, 0) = 0
)

, cls__mst_product as (
  select
    id as product_id
    , name as product_name
    , product_type_id
  from
    _l0_mysql_pos.mst_products
    inner join (
      select id, max(time) as time from _l0_mysql_pos.mst_products group by id
    ) using (id, time)
  where
    coalesce(deleted, 0) = 0
)

, cls__product_price as (
  select distinct
    mst_product_id as product_id
    , member_type
    , price_type
    , product_price
  from (
    select *
    from
      _l0_mysql_pos.mst_product_prices
      inner join (
        select
          mst_product_id
          , max(time) as time
        from
          _l0_mysql_pos.mst_product_prices
        where
          deleted = 0
          and price_serial = 1
        group by
          mst_product_id
      ) using (mst_product_id, time)
    where
      deleted = 0
      and price_serial = 1
  )
  cross join unnest (
    array[1, 1, 2, 2, 3, 3, 4, 4],
    array[1, 2, 1, 2, 1, 2, 1, 2],
    array[
      app_member_course_price,
      app_member_option_price,
      card_member_course_price,
      card_member_option_price,
      non_member_course_price,
      non_member_option_price,
      senior_member_course_price,
      senior_member_option_price
    ]
  ) as t(member_type, price_type, product_price)
  where
    product_price is not null
)


, cls__nomination as (
  select distinct
    order_detail_id
    , mst_therapist_id as therapist_id
    , therapist_no
    , nomination_fee
    , treatment_minutes as treatment_minutes_tp
  from
    _l0_mysql_pos.therapist_nominations
    inner join (
        select id, max(time) as time
        from _l0_mysql_pos.therapist_nominations
        group by id
      ) using (id, time)
  where
    coalesce(deleted, 0) = 0
)
, cls__reward as (
  select distinct
    order_detail_id
    , reward_item_id
    , reward_item_value
  from
    _l0_mysql_pos.order_detail_reward_items
    inner join (
        select id, max(time) as time
        from _l0_mysql_pos.order_detail_reward_items
        group by id
      ) using (id, time)
  where
    coalesce(deleted, 0) = 0
)

, merged as (
  select
    order_id
    , business_date
    , reservation_id
    , property_id
    , customer_id
    , phone_no
    , email
    , therapist_id
    , therapist_no
    , parent_order_id
    , treatment_minutes
    , start_time as order_start_time
    , treatment_minutes_tp
    , is_repeat
    , member_type
    , order_detail_id
    , product_id
    , product_name
    , price_type
    , product_type_id
    , if(coalesce(product_price, sales_price) - sales_price = 620, floor(620 / tax_rate), 0) as hr_discount
    , if(category_id <> 310 and product_type_id in (1, 4), ceiling(nomination_fee / tax_rate), 0) as nomination_fee
    , if(
        reward_item_id = 2040102
        and substr(cast(category_id as varchar), length(cast(category_id as varchar)) - 2, 3) <> '310'
        and product_type_id in (1, 4),
        ceiling(reward_item_value / tax_rate),
        0
      ) as royalty_program_discount
    , if(category_id <> 310 and product_type_id in (1, 4), ceiling(sales_price / tax_rate), 0) as uriage_sejutsu
  from
    cls__order_detail
    inner join cls__order using (order_id)
    left join cls__mst_product using (product_id)
    left join cls__product_price using (product_id, member_type, price_type)
    left join cls__nomination using (order_detail_id)
    left join cls__reward using (order_detail_id)
)

, merged_with_tp_time as (
  select
    *
    , order_start_time
      + 60 * coalesce(
          sum(treatment_minutes_tp) over (
            partition by order_id
            order by
              order_start_time + 60 * treatment_minutes_tp,
              order_detail_id,
              therapist_no
            rows between unbounded preceding and 1 preceding
          ),
          0
        ) as start_time
    , order_start_time
      + 60 * sum(treatment_minutes_tp) over (
          partition by order_id
          order by
            order_start_time + 60 * treatment_minutes_tp,
            order_detail_id,
            therapist_no
          rows between unbounded preceding and current row
        ) as end_time
  from
    merged
)

, allocated_time as (
  select
    *
    , case 
        when product_type_id = 4
          and coalesce(treatment_minutes_tp, 0) = 0
          then order_start_time
        else start_time
      end as allocated_start_time

    , case
        when product_type_id = 4
          and coalesce(treatment_minutes_tp, 0) = 0
          then order_start_time
        else end_time
      end as allocated_end_time
  from
    merged_with_tp_time
)

select distinct
  td_time_parse(business_date, 'jst') as time
  , td_time_string(td_time_parse(business_date, 'jst'), 's!', 'jst') as time_fmt
  , 'business_date' as time_means
  , order_id
  , business_date
  , reservation_id
  , property_id
  , customer_id
  , phone_no
  , email
  , therapist_id
  , parent_order_id
  , treatment_minutes
  , allocated_start_time as start_time
  , allocated_end_time as end_time
  , is_repeat
  , member_type
  , order_detail_id
  , product_id
  , product_name
  , price_type
  , product_type_id
  , hr_discount
  , nomination_fee
  , royalty_program_discount
  , uriage_sejutsu
  , business_hour
  , slot_from
  , slot_to

  , rank() over (
      partition by order_id
      order by order_detail_id
    ) as order_detail_id_seq

  , row_number() over (
      partition by order_id
      order by order_detail_id, business_hour
    ) as order_id_hour_seq

  , row_number() over (
      partition by order_id, order_detail_id
      order by business_hour
    ) as order_detail_id_hour_seq

  , case
      when product_type_id = 4
        and coalesce(treatment_minutes_tp, 0) = 0
        then 0
      else (
        least(slot_to, allocated_end_time)
        - greatest(slot_from, allocated_start_time)
      ) / 60
    end as treatment_minutes_in_hour

  , uriage_sejutsu
      + nomination_fee
      + hr_discount
      - royalty_program_discount as uriage1

  , uriage_sejutsu
      + hr_discount
      - royalty_program_discount as uriage

from
  allocated_time

  inner join (
    select distinct
      business_date
      , business_hour
      , td_time_parse(business_datetime, 'jst') as slot_from
      , td_time_add(
          td_time_parse(business_datetime, 'jst'),
          '1h'
        ) as slot_to
    from
      _integration_datamart.mst_datetime
  ) using (business_date)

where
  (
    treatment_minutes_tp > 0
    and least(slot_to, allocated_end_time)
        - greatest(slot_from, allocated_start_time) > 0
  )
  or
  (
    product_type_id = 4
    and coalesce(treatment_minutes_tp, 0) = 0
    and allocated_start_time >= slot_from
    and allocated_start_time < slot_to
  )