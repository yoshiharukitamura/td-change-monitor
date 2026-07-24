delete from l2_customer_suggest.suggest_rawdata where time = td_date_trunc('day', td_scheduled_time(), 'jst');

insert into l2_customer_suggest.suggest_rawdata
with target_customer as (
  select
    customer_id
    , r_week
  from
    _integration_datamart.hst_daily_customer_rf
  where
    time = td_date_trunc('day', td_scheduled_time(), 'jst')
    and r_week in (3, 7, 11, 15)
)
, last_order as (
  select
    r_week
    , is_repeat
    , nomination_fee
    , customer_id
    , property_id
    , shop_no
    , shop_name
    , pref_name
    , area_name
    , therapist_id
    , professional_name
    , substr('月火水木金土日', dow(cast(business_date as date)), 1) as business_dow
    , business_hour
    , row_number() over (partition by customer_id order by order_id desc, start_time, business_hour, treatment_minutes desc) as seq
    , substr('月火水木金土日', dow(cast(td_time_string(td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '2d', 'jst'), 'd!', 'jst') as date)), 1) as target_dow
  from
    _integration_datamart.cls_order_detail
    inner join target_customer using (customer_id)
    inner join (
      select property_id, shop_no, shop_name, pref_name, area_name 
      from _integration_datamart.mst_shop
      where status = '02'
    ) using (property_id)
    left join (select therapist_id, therapist_no, professional_name from _integration_datamart.mst_therapist) using (therapist_id)
  where
    time >= td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-364d', 'jst')
)
, tp_entry as (
  select
    therapist_id
    , property_id
    , business_date
    , min(business_hour) as entry_from
    , max(business_hour) as entry_to
    , max(business_hour) - min(business_hour) + 1 as entry_hour
    , row_number() over (partition by therapist_id, property_id order by business_date) as tp_recommend_seq
  from
    _integration_datamart.cls_time_slot_detail
  where
    time between td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '1d', 'jst') and td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '3d', 'jst')
  group by
    therapist_id
    , property_id
    , business_date
)
, tp_lw_entry as (
  select
    therapist_id
    , property_id
    , td_time_string(td_time_add(business_date, '7d', 'jst'), 'd!', 'jst') as business_date
    , max(business_hour) - min(business_hour) + 1 as lw_entry_hour
  from
    _integration_datamart.cls_time_slot_detail
  where
    time between td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-6d', 'jst') and td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-4d', 'jst')
  group by
    therapist_id
    , property_id
    , business_date  
)
, tp_lw_treatment as (
  select
    therapist_id
    , property_id
    , td_time_string(td_time_add(business_date, '7d', 'jst'), 'd!', 'jst') as business_date
    , sum(treatment_minutes_in_hour) as lw_treatment_minutes
  from
    _integration_datamart.cls_order_detail
  where
    time between td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-6d', 'jst') and td_time_add(td_date_trunc('day', td_scheduled_time(), 'jst'), '-4d', 'jst')
    and order_detail_id_seq = 1
  group by
    therapist_id
    , property_id
    , business_date
)
, tp_lw_sufficiency as (
  select
    therapist_id
    , property_id
    , lw_entry_hour
    , lw_treatment_minutes
    , coalesce(lw_treatment_minutes, 0)/60.0/lw_entry_hour as lw_sufficiency
  from
    (select therapist_id, property_id, sum(lw_entry_hour) as lw_entry_hour from tp_lw_entry group by therapist_id, property_id)
    left join (select therapist_id, property_id, sum(lw_treatment_minutes) as lw_treatment_minutes from tp_lw_treatment group by therapist_id, property_id) using (therapist_id, property_id)
)
, suggest_tp_other as (
  select
    customer_id
    , property_id
    , tp_name
    , tp_slot1
    , tp_slot2
    , tp_slot3
    , sum_entry_hour
    , lw_entry_hour
    , lw_treatment_minutes
    , lw_sufficiency
    , row_number() over (partition by customer_id, property_id order by sum_entry_hour desc, lw_sufficiency) as tp_seq
  from
    last_order
    left join (
      select
        property_id
        , therapist_id as tp_id
        , tp_name
        , td_time_format(td_time_parse(min(if(tp_recommend_seq=1, business_date)), 'jst'), 'M/d', 'jst')
          ||' ('||substr('月火水木金土日', dow(cast(min(if(tp_recommend_seq=1, business_date)) as date)), 1)||') '
          ||cast(min(if(tp_recommend_seq=1, entry_from)) as varchar)||':00-'
          ||cast(min(if(tp_recommend_seq=1, entry_to))+1 as varchar)||':00' as tp_slot1
        , td_time_format(td_time_parse(min(if(tp_recommend_seq=2, business_date)), 'jst'), 'M/d', 'jst')
          ||' ('||substr('月火水木金土日', dow(cast(min(if(tp_recommend_seq=2, business_date)) as date)), 1)||') '
          ||cast(min(if(tp_recommend_seq=2, entry_from)) as varchar)||':00-'
          ||cast(min(if(tp_recommend_seq=2, entry_to))+1 as varchar)||':00' as tp_slot2
        , td_time_format(td_time_parse(min(if(tp_recommend_seq=3, business_date)), 'jst'), 'M/d', 'jst')
          ||' ('||substr('月火水木金土日', dow(cast(min(if(tp_recommend_seq=3, business_date)) as date)), 1)||') '
          ||cast(min(if(tp_recommend_seq=3, entry_from)) as varchar)||':00-'
          ||cast(min(if(tp_recommend_seq=3, entry_to))+1 as varchar)||':00' as tp_slot3
        , sum(entry_hour) as sum_entry_hour
      from
        tp_entry
        left join (select therapist_id, professional_name as tp_name from _integration_datamart.mst_therapist) using (therapist_id)
      group by
        therapist_id, property_id, tp_name
    ) using (property_id)
    left join (select therapist_id as tp_id, property_id, lw_entry_hour, lw_treatment_minutes, lw_sufficiency from tp_lw_sufficiency) using (tp_id, property_id)
  where
    seq = 1
    and business_dow = target_dow
    and therapist_id <> tp_id
)

select
  r_week
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then 'A-1'
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then 'A-2'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then 'B-1'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then 'B-2'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then 'C-1'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then 'C-2'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then 'D-1'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then 'D-2'
    end as pattern
  , if(is_repeat = 1, '既存', '新規') as is_repeat
  , if(nomination_fee > 100, '指名TP', '前回施術TP') as is_nomination
  , nomination_fee
  , property_id
  , shop_no
  , shop_name
  , pref_name
  , area_name
  , customer_id
  , therapist_id
  , professional_name
  , business_dow
  , 'ご利用のお礼とご予約のご案内' as subject
  -- , case
  --     when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then 'ご指名セラピストの空き状況のご案内'
  --     when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then 'セラピストの空き状況のご案内'
  --     when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then 'ご利用のお礼とご予約のご案内'
  --     when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then 'ご利用のお礼とご予約のご案内'
  --     when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then 'ご指名セラピストの空き状況のご案内'
  --     when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then 'セラピストの空き状況のご案内'
  --     when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then 'ご利用のお礼とご予約のご案内'
  --     when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then 'ご利用のお礼とご予約のご案内'
  --   end as subject
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then 'りらくる'||shop_name||'をご利用いただき、ありがとうございます。'
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then 'りらくる'||shop_name||'をご利用いただき、ありがとうございます。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then 'りらくる'||shop_name||'をご利用いただき、ありがとうございます。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then 'りらくる'||shop_name||'をご利用いただき、ありがとうございます。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then 'いつもりらくる'||shop_name||'をご利用いただき、ありがとうございます。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then 'いつもりらくる'||shop_name||'をご利用いただき、ありがとうございます。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then 'いつもりらくる'||shop_name||'をご利用いただき、ありがとうございます。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then 'いつもりらくる'||shop_name||'をご利用いただき、ありがとうございます。'
    end as header_1
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then '前回にご指名いただいたセラピスト［'||tp1_name||'］の入店状況をご案内いたします。'
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then 'ご担当させていただきましたセラピストの施術にご満足いただけましたでしょうか？'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then 'ご担当させていただきましたセラピストの施術にご満足いただけましたでしょうか？'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then 'ご担当させていただきましたセラピストの施術にご満足いただけましたでしょうか？'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then '前回にご指名いただいたセラピスト［'||tp1_name||'］の入店状況をご案内いたします。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then 'ご担当させていただきましたセラピストの施術にご満足いただけましたでしょうか？'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then 'ご担当させていただきましたセラピストの施術にご満足いただけましたでしょうか？'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then 'ご担当させていただきましたセラピストの施術にご満足いただけましたでしょうか？'
    end as header_2
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then '他にもセラピストがいますので、加えてご紹介させていただきます。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then '他にもセラピストがいますので、加えてご紹介させていただきます。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then '他にもセラピストがいますので、加えてご紹介させていただきます。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then '他にもセラピストがいますので、加えてご紹介させていただきます。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then '他にもセラピストがいますので、加えてご紹介させていただきます。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then '他にもセラピストがいますので、加えてご紹介させていただきます。'
    end as header_3
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then professional_name
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp1_name||'（前回担当）'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then professional_name
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then professional_name
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp1_name||'（前回担当）'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then professional_name
    end as body_1_1
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then tp1_slot1
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then '大変申し訳ございませんが、直近3日間に入店の予定がございません。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp1_slot1
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then '大変申し訳ございませんが、直近3日間に入店の予定がございません。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then tp1_slot1
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then '大変申し訳ございませんが、直近3日間に入店の予定がございません。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp1_slot1
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then '大変申し訳ございませんが、直近3日間に入店の予定がございません。'
    end as body_1_2
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then tp1_slot2
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then '前回担当セラピストをご希望の場合は以下のURLから入店状況をご確認ください。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp1_slot2
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then '前回担当セラピストをご希望の場合は以下のURLから入店状況をご確認ください。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then tp1_slot2
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then '前回担当セラピストをご希望の場合は以下のURLから入店状況をご確認ください。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp1_slot2
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then '前回担当セラピストをご希望の場合は以下のURLから入店状況をご確認ください。'
    end as body_1_3
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then tp1_slot3
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then 'https://relxle.com/launch_app?state=calendar&shop_id='||shop_no
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp1_slot3
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then 'https://relxle.com/launch_app?state=calendar&shop_id='||shop_no
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then tp1_slot3
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then 'https://relxle.com/launch_app?state=calendar&shop_id='||shop_no
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp1_slot3
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then 'https://relxle.com/launch_app?state=calendar&shop_id='||shop_no
    end as body_1_4
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then '前回のセラピストご予約はこちらへ'
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then '前回のセラピストのその他のスケジュールを確認する'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then '前回のセラピストご予約はこちらへ'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then '前回のセラピストのその他のスケジュールを確認する'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then '前回のセラピストご予約はこちらへ'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then '前回のセラピストのその他のスケジュールを確認する'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then '前回のセラピストご予約はこちらへ'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then '前回のセラピストのその他のスケジュールを確認する'
    end as body_1_5
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then 'なお、空き状況は随時変動しております。'
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then '前回ご来店いただいた店舗のセラピストをご紹介いたします。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then '前回ご来店いただいた店舗のセラピストをご紹介いたします。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then '前回ご来店いただいた店舗のセラピストをご紹介いたします。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then 'なお、空き状況は随時変動しております。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then '前回ご来店いただいた店舗のセラピストをご紹介いたします。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then '前回ご来店いただいた店舗のセラピストをご紹介いたします。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then '前回ご来店いただいた店舗のセラピストをご紹介いたします。'
    end as body_2_1
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then 'ご希望の日時が埋まる前に、ぜひお早めにご予約くださいませ。'
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then ''
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then 'ご希望の日時が埋まる前に、ぜひお早めにご予約くださいませ。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then ''
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then ''
    end as body_2_2
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then tp2_name
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp2_name
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then tp2_name
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then tp2_name
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp2_name
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then tp2_name
    end as body_3_1
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then tp2_slot1
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp2_slot1
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then tp2_slot1
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then tp2_slot1
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp2_slot1
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then tp2_slot1
    end as body_3_2
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then tp2_slot2
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp2_slot2
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then tp2_slot2
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then tp2_slot2
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp2_slot2
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then tp2_slot2
    end as body_3_3
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then tp2_slot3
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp2_slot3
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then tp2_slot3
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then tp2_slot3
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp2_slot3
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then tp2_slot3
    end as body_3_4
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then tp3_name
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp3_name
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then tp3_name
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then tp3_name
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp3_name
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then tp3_name
    end as body_4_1
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then tp3_slot1
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp3_slot1
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then tp3_slot1
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then tp3_slot1
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp3_slot1
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then tp3_slot1
    end as body_4_2
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then tp3_slot2
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp3_slot2
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then tp3_slot2
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then tp3_slot2
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp3_slot2
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then tp3_slot2
    end as body_4_3
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then tp3_slot3
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then tp3_slot3
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then tp3_slot3
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then tp3_slot3
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then tp3_slot3
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then tp3_slot3
    end as body_4_4
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then 'なお、空き状況は随時変動しております。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then 'なお、空き状況は随時変動しております。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then 'なお、空き状況は随時変動しております。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then 'なお、空き状況は随時変動しております。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then 'なお、空き状況は随時変動しております。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then 'なお、空き状況は随時変動しております。'
    end as footer_1
  , case
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 0 and nomination_fee >= 100 and tp1_name is null then 'ご希望の日時が埋まる前に、ぜひお早めにご予約くださいませ。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is not null then 'ご希望の日時が埋まる前に、ぜひお早めにご予約くださいませ。'
      when is_repeat = 0 and nomination_fee < 100 and tp1_name is null then 'ご希望の日時が埋まる前に、ぜひお早めにご予約くださいませ。'
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is not null then ''
      when is_repeat = 1 and nomination_fee >= 100 and tp1_name is null then 'ご希望の日時が埋まる前に、ぜひお早めにご予約くださいませ。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is not null then 'ご希望の日時が埋まる前に、ぜひお早めにご予約くださいませ。'
      when is_repeat = 1 and nomination_fee < 100 and tp1_name is null then 'ご希望の日時が埋まる前に、ぜひお早めにご予約くださいませ。'
    end as footer_2
  , 'https://relxle.com/launch_app?state=calendar&shop_id='||shop_no as url
  , tp1_name
  , tp1_slot1
  , tp1_slot2
  , tp1_slot3
  , tp2_name
  , tp2_slot1
  , tp2_slot2
  , tp2_slot3
  , tp3_name
  , tp3_slot1
  , tp3_slot2
  , tp3_slot3
  , td_date_trunc('day', td_scheduled_time(), 'jst') as time
from
  last_order
  left join (
      select
        therapist_id, property_id
        , tp1_name
        , td_time_format(td_time_parse(min(if(tp_recommend_seq=1, business_date)), 'jst'), 'M/d', 'jst')
          ||' ('||substr('月火水木金土日', dow(cast(min(if(tp_recommend_seq=1, business_date)) as date)), 1)||') '
          ||cast(min(if(tp_recommend_seq=1, entry_from)) as varchar)||':00-'
          ||cast(min(if(tp_recommend_seq=1, entry_to))+1 as varchar)||':00' as tp1_slot1
        , td_time_format(td_time_parse(min(if(tp_recommend_seq=2, business_date)), 'jst'), 'M/d', 'jst')
          ||' ('||substr('月火水木金土日', dow(cast(min(if(tp_recommend_seq=2, business_date)) as date)), 1)||') '
          ||cast(min(if(tp_recommend_seq=2, entry_from)) as varchar)||':00-'
          ||cast(min(if(tp_recommend_seq=2, entry_to))+1 as varchar)||':00' as tp1_slot2
        , td_time_format(td_time_parse(min(if(tp_recommend_seq=3, business_date)), 'jst'), 'M/d', 'jst')
          ||' ('||substr('月火水木金土日', dow(cast(min(if(tp_recommend_seq=3, business_date)) as date)), 1)||') '
          ||cast(min(if(tp_recommend_seq=3, entry_from)) as varchar)||':00-'
          ||cast(min(if(tp_recommend_seq=3, entry_to))+1 as varchar)||':00' as tp1_slot3
      from
        tp_entry
        left join (select therapist_id, professional_name as tp1_name from _integration_datamart.mst_therapist) using (therapist_id)
      group by
        therapist_id, property_id, tp1_name
    ) using (therapist_id, property_id)
  left join (
      select
        customer_id
        , property_id
        , min(if(tp_seq=1, tp_name)) as tp2_name
        , min(if(tp_seq=1, tp_slot1)) as tp2_slot1
        , min(if(tp_seq=1, tp_slot2)) as tp2_slot2
        , min(if(tp_seq=1, tp_slot3)) as tp2_slot3
        , min(if(tp_seq=2, tp_name)) as tp3_name
        , min(if(tp_seq=2, tp_slot1)) as tp3_slot1
        , min(if(tp_seq=2, tp_slot2)) as tp3_slot2
        , min(if(tp_seq=2, tp_slot3)) as tp3_slot3
      from
        suggest_tp_other
      group by
        customer_id
        , property_id
    ) using (customer_id, property_id)
where
  seq = 1
  and business_dow = target_dow
