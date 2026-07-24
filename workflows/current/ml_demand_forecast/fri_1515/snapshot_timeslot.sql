with shop_master as (
  select
    no as shop_no
    , id as property_id
    , name as shop_name
  from
    _l1_mysql_pos.mst_shops
)
, therapist_master as (
  select
    coalesce(no, 'id-'||cast(id as varchar)) as therapist_no
    , id as therapist_id
  from
    _l1_mysql_pos.mst_therapists
)
, data_agg as (
  select
    td_time_string(td_date_trunc('week', time, 'jst'), 'd!', 'jst') as processing_date
    , td_time_string(time, 's!', 'jst') as snapshot_datetime
    , td_time_string(td_date_trunc('week', td_time_parse(date, 'jst'), 'jst'), 'd!', 'jst') as business_week
    , shop_no
    , shop_name
    , therapist_no
    , sum(if(cast(end_time as bigint)-cast(start_time as bigint)=100, 1, 0.5)) as time_slot
  from
    l0_core.time_slot_detail_fri_ss
    left join shop_master using (property_id)
    left join therapist_master using (therapist_id)
  where
    td_time_range(time, '2025-01-06', null, 'jst')
    and entry_status = '04'
  group by
    1,2,3,4,5,6
)

select
  processing_date
  , snapshot_datetime
  , business_week
  , 'クエスト発動時点' as aggregate_timing
  , shop_no
  , shop_name
  , therapist_no
  , time_slot
from
  data_agg
order by
  processing_date
  , business_week
  , shop_no
  , therapist_no
