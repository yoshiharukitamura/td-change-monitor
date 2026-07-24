with merged as (
  select
    t0.therapist_id
    , t0.therapist_no
    , t0.work_saturday as work_saturday_th
    , t0.work_sunday as work_sunday_th
    , t0.week_days as week_days_th
    , t0.daily_work_hours as daily_work_hours_th
    , t1.work_saturday as work_saturday_ap
    , t1.work_sunday as work_sunday_ap
    , t1.week_days as week_days_ap
    , t1.daily_work_hours as daily_work_hours_ap
  from (
    select
      *
    from _l1_mysql_core.therapist 
  ) as t0
  left join (
    select
      *
    from _l1_mysql_core.applicant
  ) as t1
  on t0.therapist_id = t1.therapist_id
  where t1.therapist_id is not null
        and coalesce(t0.deleted, 0) = 0
        and coalesce(t1.deleted, 0) = 0
)

, array_hours_days as (
  select
    therapist_id
    , therapist_no
    , src
    , week_days
    , daily_work_hours
    , work_saturday
    , work_sunday
  from merged
  cross join unnest(
    array['th', 'ap'], array[week_days_th, week_days_ap], array[daily_work_hours_th, daily_work_hours_ap], array[work_saturday_th, work_saturday_ap], array[work_sunday_th, work_sunday_ap]
  ) as t(src, week_days, daily_work_hours, work_saturday, work_sunday)
)

, normalized_symbols as (
  select
    therapist_id
    , therapist_no
    , src
    , week_days
    , daily_work_hours
    , work_saturday
    , work_sunday
    --小文字化,空白除去,全角数字波線を半角ハイフン
    , regexp_replace(translate(regexp_replace(lower(coalesce(week_days, '')), '\\s+', '')
        , '０１２３４５６７８９〜～—–−', '0123456789------')
        , '[ー]{2,}', '-'
      ) as norm_week_days
  from array_hours_days
)

, extract_nums as (
  select
    therapist_id
    , therapist_no
    , src
    , week_days
    , daily_work_hours
    , work_saturday
    , work_sunday
    , norm_week_days
    --数字を抽出し0~7に限定
    , filter(transform(regexp_extract_all(norm_week_days, '[0-9]{1,2}'), x -> cast(x as int))
        , x -> x between 0 and 7
    ) as extract_num_week_days
  from normalized_symbols
)

, normalized_ja as (
  select
    therapist_id
    , therapist_no
    , src
    , if(work_saturday = '01', 1, 0) as work_saturday
    , if(work_sunday = '01', 1, 0) as work_sunday
    , extract_num_week_days
    , norm_week_days
    , case
        when cardinality(extract_num_week_days) >= 2 then element_at(array_sort(extract_num_week_days), 1)
        when cardinality(extract_num_week_days) = 1 and regexp_like(norm_week_days, '以上|>=|\\+') then element_at(extract_num_week_days, 1)
        when cardinality(extract_num_week_days) = 1 and regexp_like(norm_week_days, '以下|<=|未満') then 0
        when cardinality(extract_num_week_days) = 1 then element_at(extract_num_week_days, 1)
        when regexp_like(norm_week_days, '何日|毎日|全日|フル') then 7
        else 0
      end as week_days_min
    , case
        when cardinality(extract_num_week_days) >= 2 then element_at(array_sort(extract_num_week_days), cardinality(extract_num_week_days))
        when cardinality(extract_num_week_days) = 1 and regexp_like(norm_week_days, '以上|>=|\\+') then 7
        when cardinality(extract_num_week_days) = 1 and regexp_like(norm_week_days, '以下|<=|未満') then element_at(extract_num_week_days, 1)
        when cardinality(extract_num_week_days) = 1 then element_at(extract_num_week_days, 1)
        when regexp_like(norm_week_days, '何日|毎日|全日|フル') then 7
        else 0
      end as week_days_max
    , case
        when daily_work_hours is null or daily_work_hours = '' then 0
        else cast(daily_work_hours as int)
      end as daily_work_hours
  from extract_nums
)

, pivoted as (
  select
    therapist_id
    , therapist_no
    , max(if(src = 'ap', work_saturday, null)) as work_saturday_ap
    , max(if(src = 'ap', work_sunday, null)) as work_sunday_ap
    , max(if(src = 'ap', week_days_min, null)) as week_days_min_ap
    , max(if(src = 'ap', week_days_max, null)) as week_days_max_ap
    , max(if(src = 'ap', daily_work_hours, null)) as daily_work_hours_ap
    , max(if(src = 'th', work_saturday, null)) as work_saturday_th
    , max(if(src = 'th', work_sunday, null)) as work_sunday_th
    , max(if(src = 'th', week_days_max)) as week_days_max_th
    , max(if(src = 'th', daily_work_hours)) as daily_work_hours_th
  from normalized_ja
  group by 1,2
)

, prep_tp_grade as (
  select
    therapist_id
    , therapist_no 
    , work_saturday_ap
    , work_sunday_ap
    , case
        when week_days_min_ap = 0 and daily_work_hours_ap = 0 then 0
        when week_days_min_ap = 0 and daily_work_hours_ap > 0 then 3
        else week_days_min_ap
      end as week_days_min_ap
    , case
        when week_days_max_ap = 0 and daily_work_hours_ap = 0 then 0
        when week_days_max_ap = 0 and daily_work_hours_ap > 0 then 3
        else week_days_max_ap
      end as week_days_max_ap
    , case
        when daily_work_hours_ap = 0 and daily_work_hours_ap = 0 then 0
        when daily_work_hours_ap = 0 and daily_work_hours_ap > 0 then 6
        else daily_work_hours_ap
      end as daily_work_hours_ap
    , work_saturday_th
    , work_sunday_th
    , case
        when week_days_max_th = 0 and week_days_max_th = 0 then 0
        when week_days_max_th = 0 and week_days_max_th > 0 then 3
        else week_days_max_th
      end as week_days_max_th
    , case
        when daily_work_hours_th = 0 and week_days_max_th = 0 then 0
        when daily_work_hours_th = 0 and week_days_max_th > 0 then 6
        else daily_work_hours_th
      end as daily_work_hours_th
  from pivoted
)

, tp_grade as (
  select
    therapist_id
    , therapist_no
    , case
        when week_days_min_ap * daily_work_hours_ap >= 40 then 'R1'
        when week_days_min_ap * daily_work_hours_ap >= 30 then 'R2'
        when week_days_min_ap * daily_work_hours_ap >= 20 then 'R3'
        when week_days_min_ap * daily_work_hours_ap >= 10 then 'Q1'
        when week_days_min_ap * week_days_max_ap > 0 then 'Q2'
        else '希望無'
      end as rq_min_ap
    , case
        when week_days_max_ap * daily_work_hours_ap >= 40 then 'R1'
        when week_days_max_ap * daily_work_hours_ap >= 30 then 'R2'
        when week_days_max_ap * daily_work_hours_ap >= 20 then 'R3'
        when week_days_max_ap * daily_work_hours_ap >= 10 then 'Q1'
        when week_days_max_ap * daily_work_hours_ap > 0 then 'Q2'
        else '希望無'
      end as rq_max_ap
    , case
        when ((week_days_min_ap + week_days_max_ap) / 2.0) * daily_work_hours_ap >= 40 then 'R1'
        when ((week_days_min_ap + week_days_max_ap) / 2.0) * daily_work_hours_ap >= 30 then 'R2'
        when ((week_days_min_ap + week_days_max_ap) / 2.0) * daily_work_hours_ap >= 20 then 'R3'
        when ((week_days_min_ap + week_days_max_ap) / 2.0) * daily_work_hours_ap >= 10 then 'Q1'
        when ((week_days_min_ap + week_days_max_ap) / 2.0) * daily_work_hours_ap > 0 then 'Q2'
        else '希望無'
      end as rq_avg_ap
    , case
        when daily_work_hours_ap >= 2 and work_saturday_ap = 1 and work_sunday_ap = 1 then 'A'
        when daily_work_hours_ap >= 4 and (work_saturday_ap = 1 or work_sunday_ap = 1) then 'A'
        else 'B'
      end as weekend_ap
    , case
        when week_days_max_th * daily_work_hours_th >= 40 then 'R1'
        when week_days_max_th * daily_work_hours_th >= 30 then 'R2'
        when week_days_max_th * daily_work_hours_th >= 20 then 'R3'
        when week_days_max_th * daily_work_hours_th >= 10 then 'Q1'
        when week_days_max_th * daily_work_hours_th > 0 then 'Q2'
        else '希望無'
      end as rq_max_th
    , case
        when daily_work_hours_th >= 2 and work_saturday_th = 1 and work_sunday_th = 1 then 'A'
        when daily_work_hours_th >= 4 and (work_saturday_ap = 1 or work_sunday_ap = 1) then 'A'
        else 'B'
      end as weekend_th
  from prep_tp_grade
)

, tp_th_ap_requests as (
  select
    therapist_id
    --, therapist_no
    , if(rq_min_ap = '希望無', '希望無', rq_min_ap || '-' || weekend_ap) as min_applicant_reqenst
    , if(rq_avg_ap = '希望無', '希望無', rq_avg_ap || '-' || weekend_ap) as avg_applicant_reqenst
    , if(rq_max_ap = '希望無', '希望無', rq_max_ap || '-' || weekend_ap) as max_applicant_reqenst
    , if(rq_max_th = '希望無', '希望無', rq_max_th || '-' || weekend_th) as max_nuturing_reqenst
  from tp_grade
)

, tp_contacts as (
  select
    therapist_id
    , email
    , tel01
    , tel02
    , tel03
  from
    _l1_mysql_core.therapist_contact
  where
    deleted = 0
)

, prep_first_entry as (
  select
    therapist_no
    , substr(business_date, 1, 10) as business_date
    , case
        when substr(business_date, 1, 10) <= '2022-11-30' then ((td_time_parse(end_time, 'jst') - td_time_parse(start_time, 'jst')) / 60.0) - coalesce(break_time, 0)
        else facilities_usage_time
      end as facilities_usage_time
  from
    _l1_mysql_core.therapist_daily_report
  where
    coalesce(deleted, 0) = 0
)

, first_entry as (
  select
    therapist_no
    , min(business_date) as first_entry_date
  from
    prep_first_entry
  where
    facilities_usage_time > 0
  group by
    1
)

select
  ${session_unixtime} as time
  , td_time_string(${session_unixtime}, 's!', 'jst') as time_fmt
  , 'wf_session_time' as time_means
  , therapist_id
  , therapist_no
  , name as therapist_name
  , professional_name
  , case
      when cast(therapist_no as bigint) between 9700001 and 9799999 then 1
      when cast(therapist_no as bigint) between 9800001 and 9899999 then 2
      when cast(therapist_no as bigint) between 9900009 and 9924707 then 2
      when coalesce(s_rank_flag, 0) = 0 then 0
      else 3
    end as division
  , case sex_type
      when '01' then '男性'
      when '02' then '女性'
      else '-'
    end as gender
  , date_diff('year', cast(substr(birthday, 1, 10) as date), cast('${session_date}' as date)) as age
  , certificate_zip as zip_code
  , pref_name
  , pref_sort
  , area_name
  , area_sort
  , old_therapist_id
  , hope_property_id_1
  , hope_property_id_2
  , first_entry_date
  , work_saturday
  , work_sunday
  , work_holiday
  , week_days
  , timezone
  , introducer_therapist_id
  , contract_type
  , min_applicant_reqenst
  , avg_applicant_reqenst
  , max_applicant_reqenst
  , max_nuturing_reqenst
  , email
  , tel01
  , tel02
  , tel03
from
  _l1_mysql_core.therapist
  left join (
    select
      therapist_id
      , s_rank_flag
    from
      _l1_mysql_core.therapist_skill
    ) using (therapist_id)
  left join (
    select
      therapist_id
      , contract_type
    from
      _l1_mysql_core.therapist_contract
  ) using (therapist_id)
  left join (select cast(id as varchar) as certificate_pref_code, name as pref_name, sort_order as pref_sort, mst_area_id from _l1_mysql_pos.mst_prefectures) using (certificate_pref_code)
  left join (select id as mst_area_id, name as area_name, sort_order as area_sort from _l1_mysql_pos.mst_areas) using (mst_area_id)
  left join tp_th_ap_requests using (therapist_id)
  left join tp_contacts using (therapist_id)
  left join first_entry using (therapist_no)
where
  therapist_no is not null