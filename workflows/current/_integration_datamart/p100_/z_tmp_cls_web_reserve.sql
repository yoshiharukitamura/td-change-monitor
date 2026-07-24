with map_dec_enc as (
  select
    num as reserve_id_dec
    , bjhxn1lpstrvywnuvxdhmgvpcgr2ut09 as reserve_id_enc
    , num as reservation_id
  from
    l0_csv_upload.map_reservation_ids
  where
    num != '0'
)
, reserve_id_dec_list as (
  select reserve_id as reserve_id_dec, min(pv_id) as pv_id
  from l1_website_access.trs_ga_session
  where td_path = '/usr/reservations/complete' and length(reserve_id) > 0
  group by reserve_id
)
, reserve_id_enc_list as (
  select reserve_id as reserve_id_enc, min(pv_id) as pv_id
  from l1_website_access.trs_ga_session
  where td_path = '/usr/reservations/complete' and length(reserve_id) > 0
  group by reserve_id
)

select
  cast(reservation_id as bigint) as reservation_id
  , case
      when dec.pv_id is not null and enc.pv_id is not null then if(dec.pv_id < enc.pv_id, dec.pv_id, enc.pv_id)
      else coalesce(dec.pv_id, enc.pv_id)
    end as pv_id
  , case
      when dec.pv_id is not null and enc.pv_id is not null then if(dec.pv_id < enc.pv_id, dec.reserve_id_dec, enc.reserve_id_enc)
      else coalesce(dec.reserve_id_dec, enc.reserve_id_enc)
    end as reserve_id
from
  map_dec_enc as map
  left join reserve_id_dec_list as dec on map.reserve_id_dec = dec.reserve_id_dec
  left join reserve_id_enc_list as enc on map.reserve_id_enc = enc.reserve_id_enc
where
  coalesce(dec.reserve_id_dec, enc.reserve_id_enc) is not null