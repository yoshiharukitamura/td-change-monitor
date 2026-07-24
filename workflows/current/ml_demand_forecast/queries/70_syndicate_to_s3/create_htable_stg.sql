with map_agg_data as (
  select
    td_time_format(td_time_parse(processing_date, 'jst'), 'YYYY/MM/dd', 'jst') as processing_date
    , mst_shop_id as property_id
    , td_time_format(td_time_parse(business_day, 'jst'), 'YYYY/MM/dd', 'jst') as business_day
    , max(is_manual_fixed) as is_manual_fixed
    , map_agg(business_hour, time_slot_restricted) as kv_rest
    , map_agg(business_hour, time_slot) as kv_ts
    , map_agg(business_hour, td1) as kv_td1
    , map_agg(business_hour, td2) as kv_td2
    , map_agg(business_hour, td3) as kv_td3
  from
    fin_timeslot_raw_vtable_fixed
  where
    time = td_date_trunc('week', td_scheduled_time(), 'jst')
  group by
    1,2,3
)

select
  processing_date
  , property_id
  , business_day

  -- , kv_rest[6] as restricted_h06
  -- , kv_rest[7] as restricted_h07
  -- , kv_rest[8] as restricted_h08
  -- , kv_rest[9] as restricted_h09
  -- , kv_rest[10] as restricted_h10
  -- , kv_rest[11] as restricted_h11
  -- , kv_rest[12] as restricted_h12
  -- , kv_rest[13] as restricted_h13
  -- , kv_rest[14] as restricted_h14
  -- , kv_rest[15] as restricted_h15
  -- , kv_rest[16] as restricted_h16
  -- , kv_rest[17] as restricted_h17
  -- , kv_rest[18] as restricted_h18
  -- , kv_rest[19] as restricted_h19
  -- , kv_rest[20] as restricted_h20
  -- , kv_rest[21] as restricted_h21
  -- , kv_rest[22] as restricted_h22
  -- , kv_rest[23] as restricted_h23
  -- , kv_rest[24] as restricted_h24
  -- , kv_rest[25] as restricted_h25
  -- , kv_rest[26] as restricted_h26
  -- , kv_rest[27] as restricted_h27
  -- , kv_rest[28] as restricted_h28
  -- , kv_rest[29] as restricted_h29

  , kv_ts[6] as rawdata_h06
  , kv_ts[7] as rawdata_h07
  , kv_ts[8] as rawdata_h08
  , kv_ts[9] as rawdata_h09
  , kv_ts[10] as rawdata_h10
  , kv_ts[11] as rawdata_h11
  , kv_ts[12] as rawdata_h12
  , kv_ts[13] as rawdata_h13
  , kv_ts[14] as rawdata_h14
  , kv_ts[15] as rawdata_h15
  , kv_ts[16] as rawdata_h16
  , kv_ts[17] as rawdata_h17
  , kv_ts[18] as rawdata_h18
  , kv_ts[19] as rawdata_h19
  , kv_ts[20] as rawdata_h20
  , kv_ts[21] as rawdata_h21
  , kv_ts[22] as rawdata_h22
  , kv_ts[23] as rawdata_h23
  , kv_ts[24] as rawdata_h24
  , kv_ts[25] as rawdata_h25
  , kv_ts[26] as rawdata_h26
  , kv_ts[27] as rawdata_h27
  , kv_ts[28] as rawdata_h28
  , kv_ts[29] as rawdata_h29

  , kv_td1[6] as dvn1_data_h06
  , kv_td1[7] as dvn1_data_h07
  , kv_td1[8] as dvn1_data_h08
  , kv_td1[9] as dvn1_data_h09
  , kv_td1[10] as dvn1_data_h10
  , kv_td1[11] as dvn1_data_h11
  , kv_td1[12] as dvn1_data_h12
  , kv_td1[13] as dvn1_data_h13
  , kv_td1[14] as dvn1_data_h14
  , kv_td1[15] as dvn1_data_h15
  , kv_td1[16] as dvn1_data_h16
  , kv_td1[17] as dvn1_data_h17
  , kv_td1[18] as dvn1_data_h18
  , kv_td1[19] as dvn1_data_h19
  , kv_td1[20] as dvn1_data_h20
  , kv_td1[21] as dvn1_data_h21
  , kv_td1[22] as dvn1_data_h22
  , kv_td1[23] as dvn1_data_h23
  , kv_td1[24] as dvn1_data_h24
  , kv_td1[25] as dvn1_data_h25
  , kv_td1[26] as dvn1_data_h26
  , kv_td1[27] as dvn1_data_h27
  , kv_td1[28] as dvn1_data_h28
  , kv_td1[29] as dvn1_data_h29

  , kv_td2[6] as dvn2_data_h06
  , kv_td2[7] as dvn2_data_h07
  , kv_td2[8] as dvn2_data_h08
  , kv_td2[9] as dvn2_data_h09
  , kv_td2[10] as dvn2_data_h10
  , kv_td2[11] as dvn2_data_h11
  , kv_td2[12] as dvn2_data_h12
  , kv_td2[13] as dvn2_data_h13
  , kv_td2[14] as dvn2_data_h14
  , kv_td2[15] as dvn2_data_h15
  , kv_td2[16] as dvn2_data_h16
  , kv_td2[17] as dvn2_data_h17
  , kv_td2[18] as dvn2_data_h18
  , kv_td2[19] as dvn2_data_h19
  , kv_td2[20] as dvn2_data_h20
  , kv_td2[21] as dvn2_data_h21
  , kv_td2[22] as dvn2_data_h22
  , kv_td2[23] as dvn2_data_h23
  , kv_td2[24] as dvn2_data_h24
  , kv_td2[25] as dvn2_data_h25
  , kv_td2[26] as dvn2_data_h26
  , kv_td2[27] as dvn2_data_h27
  , kv_td2[28] as dvn2_data_h28
  , kv_td2[29] as dvn2_data_h29

  , kv_td3[6] as dvn3_data_h06
  , kv_td3[7] as dvn3_data_h07
  , kv_td3[8] as dvn3_data_h08
  , kv_td3[9] as dvn3_data_h09
  , kv_td3[10] as dvn3_data_h10
  , kv_td3[11] as dvn3_data_h11
  , kv_td3[12] as dvn3_data_h12
  , kv_td3[13] as dvn3_data_h13
  , kv_td3[14] as dvn3_data_h14
  , kv_td3[15] as dvn3_data_h15
  , kv_td3[16] as dvn3_data_h16
  , kv_td3[17] as dvn3_data_h17
  , kv_td3[18] as dvn3_data_h18
  , kv_td3[19] as dvn3_data_h19
  , kv_td3[20] as dvn3_data_h20
  , kv_td3[21] as dvn3_data_h21
  , kv_td3[22] as dvn3_data_h22
  , kv_td3[23] as dvn3_data_h23
  , kv_td3[24] as dvn3_data_h24
  , kv_td3[25] as dvn3_data_h25
  , kv_td3[26] as dvn3_data_h26
  , kv_td3[27] as dvn3_data_h27
  , kv_td3[28] as dvn3_data_h28
  , kv_td3[29] as dvn3_data_h29

from
  map_agg_data
where
  is_manual_fixed = 1

union all

select
  processing_date
  , property_id
  , business_day

  -- , kv_rest[9] as restricted_h06
  -- , kv_rest[9] as restricted_h07
  -- , kv_rest[9] as restricted_h08
  -- , kv_rest[9] as restricted_h09
  -- , kv_rest[10] as restricted_h10
  -- , kv_rest[11] as restricted_h11
  -- , kv_rest[12] as restricted_h12
  -- , kv_rest[13] as restricted_h13
  -- , kv_rest[14] as restricted_h14
  -- , kv_rest[15] as restricted_h15
  -- , kv_rest[16] as restricted_h16
  -- , kv_rest[17] as restricted_h17
  -- , kv_rest[18] as restricted_h18
  -- , kv_rest[19] as restricted_h19
  -- , kv_rest[20] as restricted_h20
  -- , kv_rest[21] as restricted_h21
  -- , kv_rest[22] as restricted_h22
  -- , kv_rest[23] as restricted_h23
  -- , kv_rest[23] as restricted_h24
  -- , kv_rest[23] as restricted_h25
  -- , kv_rest[23] as restricted_h26
  -- , kv_rest[23] as restricted_h27
  -- , kv_rest[23] as restricted_h28
  -- , kv_rest[23] as restricted_h29

  , kv_ts[9] as rawdata_h06
  , kv_ts[9] as rawdata_h07
  , kv_ts[9] as rawdata_h08
  , kv_ts[9] as rawdata_h09
  , kv_ts[10] as rawdata_h10
  , kv_ts[11] as rawdata_h11
  , kv_ts[12] as rawdata_h12
  , kv_ts[13] as rawdata_h13
  , kv_ts[14] as rawdata_h14
  , kv_ts[15] as rawdata_h15
  , kv_ts[16] as rawdata_h16
  , kv_ts[17] as rawdata_h17
  , kv_ts[18] as rawdata_h18
  , kv_ts[19] as rawdata_h19
  , kv_ts[20] as rawdata_h20
  , kv_ts[21] as rawdata_h21
  , kv_ts[22] as rawdata_h22
  , kv_ts[23] as rawdata_h23
  , kv_ts[23] as rawdata_h24
  , kv_ts[23] as rawdata_h25
  , kv_ts[23] as rawdata_h26
  , kv_ts[23] as rawdata_h27
  , kv_ts[23] as rawdata_h28
  , kv_ts[23] as rawdata_h29

  , kv_td1[9] as dvn1_data_h06
  , kv_td1[9] as dvn1_data_h07
  , kv_td1[9] as dvn1_data_h08
  , kv_td1[9] as dvn1_data_h09
  , kv_td1[10] as dvn1_data_h10
  , kv_td1[11] as dvn1_data_h11
  , kv_td1[12] as dvn1_data_h12
  , kv_td1[13] as dvn1_data_h13
  , kv_td1[14] as dvn1_data_h14
  , kv_td1[15] as dvn1_data_h15
  , kv_td1[16] as dvn1_data_h16
  , kv_td1[17] as dvn1_data_h17
  , kv_td1[18] as dvn1_data_h18
  , kv_td1[19] as dvn1_data_h19
  , kv_td1[20] as dvn1_data_h20
  , kv_td1[21] as dvn1_data_h21
  , kv_td1[22] as dvn1_data_h22
  , kv_td1[23] as dvn1_data_h23
  , kv_td1[23] as dvn1_data_h24
  , kv_td1[23] as dvn1_data_h25
  , kv_td1[23] as dvn1_data_h26
  , kv_td1[23] as dvn1_data_h27
  , kv_td1[23] as dvn1_data_h28
  , kv_td1[23] as dvn1_data_h29

  , kv_td2[9] as dvn2_data_h06
  , kv_td2[9] as dvn2_data_h07
  , kv_td2[9] as dvn2_data_h08
  , kv_td2[9] as dvn2_data_h09
  , kv_td2[10] as dvn2_data_h10
  , kv_td2[11] as dvn2_data_h11
  , kv_td2[12] as dvn2_data_h12
  , kv_td2[13] as dvn2_data_h13
  , kv_td2[14] as dvn2_data_h14
  , kv_td2[15] as dvn2_data_h15
  , kv_td2[16] as dvn2_data_h16
  , kv_td2[17] as dvn2_data_h17
  , kv_td2[18] as dvn2_data_h18
  , kv_td2[19] as dvn2_data_h19
  , kv_td2[20] as dvn2_data_h20
  , kv_td2[21] as dvn2_data_h21
  , kv_td2[22] as dvn2_data_h22
  , kv_td2[23] as dvn2_data_h23
  , kv_td2[23] as dvn2_data_h24
  , kv_td2[23] as dvn2_data_h25
  , kv_td2[23] as dvn2_data_h26
  , kv_td2[23] as dvn2_data_h27
  , kv_td2[23] as dvn2_data_h28
  , kv_td2[23] as dvn2_data_h29

  , kv_td3[9] as dvn3_data_h06
  , kv_td3[9] as dvn3_data_h07
  , kv_td3[9] as dvn3_data_h08
  , kv_td3[9] as dvn3_data_h09
  , kv_td3[10] as dvn3_data_h10
  , kv_td3[11] as dvn3_data_h11
  , kv_td3[12] as dvn3_data_h12
  , kv_td3[13] as dvn3_data_h13
  , kv_td3[14] as dvn3_data_h14
  , kv_td3[15] as dvn3_data_h15
  , kv_td3[16] as dvn3_data_h16
  , kv_td3[17] as dvn3_data_h17
  , kv_td3[18] as dvn3_data_h18
  , kv_td3[19] as dvn3_data_h19
  , kv_td3[20] as dvn3_data_h20
  , kv_td3[21] as dvn3_data_h21
  , kv_td3[22] as dvn3_data_h22
  , kv_td3[23] as dvn3_data_h23
  , kv_td3[23] as dvn3_data_h24
  , kv_td3[23] as dvn3_data_h25
  , kv_td3[23] as dvn3_data_h26
  , kv_td3[23] as dvn3_data_h27
  , kv_td3[23] as dvn3_data_h28
  , kv_td3[23] as dvn3_data_h29

from
  map_agg_data
where
  is_manual_fixed = 0

order by
  property_id
  , business_day
