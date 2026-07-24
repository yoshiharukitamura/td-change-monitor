with therapist as (
  select
    t.therapist_id
    , t.therapist_no
    , t.professional_name
  from
    _l1_mysql_core.therapist as t
    left join _l1_mysql_core.therapist_skill as ts on t.therapist_id = ts.therapist_id
  where
    t.therapist_no is not null
    and cast(t.therapist_no as int) < 970000
    and coalesce(ts.s_rank_flag, 0) = 0
)
, slot as (
  select
    td_time_parse(working_date, 'jst') as time
    , rt.working_date as business_date
    , p.shop_no
    , t.therapist_no
    , t.professional_name
    , rt.mst_timetable_id
    , rt.start_time
    , rt.end_time
    , rt.created
    , rt.modified
    , rt.deleted
    , rt.deleted_date
  from
    _l1_mysql_reservation.resource_timetables rt
    inner join _l1_mysql_core.property p on rt.mst_shop_id = p.property_id
      and rt.working_date >= '2024-01-01'
      and rt.mst_timetable_id in (1, 3)
      and rt.status = 1 --TP時間枠において、最新の生きている枠のみ
      and rt.deleted <> 1 --削除されたものは除外
      and p.shop_brand not in ('05', '06')
    inner join _l1_mysql_reservation.mst_reservation_resources mrr on rt.mst_reservation_resource_id = mrr.id
      and mrr.mst_reservation_therapist_id >= 100
      and mrr.deleted <> 1
    inner join therapist t on mrr.mst_reservation_therapist_id = t.therapist_id
)

select * from slot

