with additional_info as (
  select
    property_id
    , substr(business_start_time, 1, 2)||':'||substr(business_start_time, 3, 2) as business_start_time
    , substr(business_end_time, 1, 2)||':'||substr(business_end_time, 3, 2) as business_end_time
    , substr(open_date, 1, 10) as open_date
    , substr(close_date, 1, 10) as close_date
    , market_population_1km
    , market_population_3km
  from
    _l1_mysql_core.property_additional_info
)

select
  ${session_unixtime} as time
  , td_time_string(${session_unixtime}, 's!', 'jst') as time_fmt
  , 'wf_session_time' as time_means
  , property_id
  , 's'||cast(property_id as varchar) as s_property_id
  , property_id as mst_shop_id
  , status
  , case
      when status = '01' then 'オープン前'
      when status = '02' then '営業中'
      when close_date is not null then '閉店済み'
      else '-'
    end as status_name
  , shop_no
  , shop_name
  , fax
  , latest_bed_num
  , zip as zip_code
  , latitude
  , longitude
  , pref_name
  , pref_sort
  , area_name
  , area_sort
  , additional_info.*
from 
  _l1_mysql_core.property
  left join (select cast(id as varchar) as pref_code, name as pref_name, sort_order as pref_sort, mst_area_id from _l1_mysql_pos.mst_prefectures) using (pref_code)
  left join (select id as mst_area_id, name as area_name, sort_order as area_sort from _l1_mysql_pos.mst_areas) using (mst_area_id)
  left join additional_info using (property_id)
where
  coalesce(shop_brand, '05') <> '05'
  and shop_no is not null
order by
  1 desc
