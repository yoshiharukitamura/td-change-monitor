select
  start_time as time
  , td_time_parse(therapy_date, 'jst') as therapy_date
  , td_time_add(td_time_parse(therapy_date, 'jst'), '-1d', 'jst') as therapy_date_1ago
  , td_date_trunc('day', td_time_parse(reservation_dt, 'jst'), 'jst') as reserve_date
  , td_time_add(td_date_trunc('day', td_time_parse(reservation_dt, 'jst'), 'jst'), '-1d', 'jst') as reserve_within_1day
  , td_time_add(td_date_trunc('day', td_time_parse(reservation_dt, 'jst'), 'jst'), '-2d', 'jst') as reserve_within_2day
  , td_time_add(td_date_trunc('day', td_time_parse(reservation_dt, 'jst'), 'jst'), '-3d', 'jst') as reserve_within_3day
  , customer_id
  , reservation_dt
  , mst_shop_no
  , mst_shop_id
  , status
  , reserved_from
  , reservation_id
  , reservation_count
from
  l1_datamart_202210.sys_reservation_logs
  left join (
      select
        id as reservation_id
        , td_time_parse(start_time, 'jst') as start_time
        , substr(start_time, 1, 10) as therapy_date
      from
        l1_reservation.reservations
  ) using (reservation_id)