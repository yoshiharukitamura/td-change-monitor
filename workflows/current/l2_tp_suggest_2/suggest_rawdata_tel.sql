with avg_entry as (
  select
    therapist_id
    , property_id
    , max(if(business_dow='月', coalesce(sum_entry_slot, 0))) as avg_mon
    , max(if(business_dow='火', coalesce(sum_entry_slot, 0))) as avg_tue
    , max(if(business_dow='水', coalesce(sum_entry_slot, 0))) as avg_wed
    , max(if(business_dow='木', coalesce(sum_entry_slot, 0))) as avg_thu
    , max(if(business_dow='金', coalesce(sum_entry_slot, 0))) as avg_fri
    , max(if(business_dow='土', coalesce(sum_entry_slot, 0))) as avg_sat
    , max(if(business_dow='日', coalesce(sum_entry_slot, 0))) as avg_sun
  from (
      select
        therapist_id
        , property_id
        , substr('月火水木金土日', dow(cast(business_date as date)), 1) as business_dow
        , sum(coalesce(entry_slot, 0))/2.0 as sum_entry_slot
      from
        _integration_datamart.cls_time_slot_detail
      where
        time between td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-14d', 'jst') and td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-1d', 'jst')
      group by
        1,2,3
    )
  group by
    therapist_id
    , property_id
)
, tp_info as (
  select
    t0.therapist_id
    , therapist_no
    , professional_name
    , coalesce(t1.tel01, t0.tel01) as tel01
  from
    _integration_datamart.mst_therapist as t0
    left join (
        select therapist_id, max_by(tel01, updated_datetime) as tel01
        from _l0_mysql_core.therapist_contact
        group by therapist_id
        having max_by(deleted, updated_datetime) = 0
      ) as t1
      on t0.therapist_id = t1.therapist_id
  where
    division = 0
)
, shop_info as (
  select
    property_id
    , shop_no
    , shop_name
    , fax
  from
    _integration_datamart.mst_shop
  where
    status = '02'
)
, entry_latest as (
  select
    td_time_parse(substr(date, 1, 10), 'jst') as time
    , td_time_string(td_time_parse(substr(date, 1, 10), 'jst'), 's!', 'jst') as time_fmt
    , 'business_date' as time_means
    , therapist_id
    , property_id
    , substr(date, 1, 10) as business_date
    , cast(substr(start_time, 1, 2) as bigint) as business_hour
    , td_time_add(td_time_parse(date, 'jst'), substr(start_time, 1, 2)||'h') as slot_from
    , td_time_add(td_time_parse(date, 'jst'), substr(end_time, 1, 2)||'h') as slot_to
    , if(substr(end_time, 3, 2) = '30', 0.5, 1.0) as entry_slot
    , date_diff('day', from_unixtime(td_date_trunc('day', td_scheduled_time(), 'jst')), from_unixtime(td_time_parse(date, 'jst'))) as diff_days
  from
    l2_tp_suggest.time_slot_detail_0630
  where
    time = td_date_trunc('day', td_scheduled_time(), 'jst')
    and (
      td_time_parse(date, 'jst') = td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-7d', 'jst')
      or td_time_parse(date, 'jst') between td_date_trunc('day', td_scheduled_time(), 'jst') and td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '7d', 'jst')
    )
    and coalesce(deleted, 0) = 0
)
, entry_latest_agg as (
  select
    therapist_id
    , property_id
    , min(if(diff_days=0, business_hour)) as today_start_hour
    , cast(min(if(diff_days=0, business_hour)) as varchar)||'-'||cast(max(if(diff_days=0, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=0, business_hour)) as varchar)||')' as hours_today
    , cast(min(if(diff_days=-7, business_hour)) as varchar)||'-'||cast(max(if(diff_days=-7, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=-7, business_hour)) as varchar)||')' as hours_lw
    , cast(min(if(diff_days=1, business_hour)) as varchar)||'-'||cast(max(if(diff_days=1, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=1, business_hour)) as varchar)||')' as hours_next1
    , cast(min(if(diff_days=2, business_hour)) as varchar)||'-'||cast(max(if(diff_days=2, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=2, business_hour)) as varchar)||')' as hours_next2
    , cast(min(if(diff_days=3, business_hour)) as varchar)||'-'||cast(max(if(diff_days=3, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=3, business_hour)) as varchar)||')' as hours_next3
    , cast(min(if(diff_days=4, business_hour)) as varchar)||'-'||cast(max(if(diff_days=4, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=4, business_hour)) as varchar)||')' as hours_next4
    , cast(min(if(diff_days=5, business_hour)) as varchar)||'-'||cast(max(if(diff_days=5, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=5, business_hour)) as varchar)||')' as hours_next5
    , cast(min(if(diff_days=6, business_hour)) as varchar)||'-'||cast(max(if(diff_days=6, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=6, business_hour)) as varchar)||')' as hours_next6
    , cast(min(if(diff_days=7, business_hour)) as varchar)||'-'||cast(max(if(diff_days=7, business_hour+1)) as varchar)||' : ('
        ||cast(count(distinct if(diff_days=7, business_hour)) as varchar)||')' as hours_next7
  from
    entry_latest
  group by
    therapist_id
    , property_id
)
, shop_suffiency as (
  select
    property_id
    , sum(treatment_minutes)/60.0/sum(entry_slot) as lw_suffiency
  from
    _integration_datamart.cls_sufficiency
  where
    time = td_time_add(td_date_trunc('week', td_scheduled_time(), 'jst'), '-7d', 'jst')
  group by
    property_id

)

select
  td_date_trunc('day', td_scheduled_time(), 'jst') as time
  , shop_no
  , shop_name
  , fax
  , 'https://www2.riraku-sys.jp/admin/shop/daytimebucket/date/'||td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst')
      ||'/property_id/'||cast(property_id as varchar)||'#'||td_time_string(td_date_trunc('day', td_scheduled_time(), 'jst'), 'd!', 'jst') as url
  , therapist_no
  , professional_name
  , tel01
  , avg_mon
  , avg_tue
  , avg_wed
  , avg_thu
  , avg_fri
  , avg_sat
  , avg_sun
  , hours_today
  , hours_lw
  , hours_next1
  , hours_next2
  , hours_next3
  , hours_next4
  , hours_next5
  , hours_next6
  , hours_next7
  , rank() over (order by lw_suffiency desc, shop_no) as rnk
  , today_start_hour
from
  entry_latest_agg
  left join avg_entry using (therapist_id, property_id)
  inner join tp_info using (therapist_id)
  inner join shop_info using (property_id)
  left join shop_suffiency using (property_id)
