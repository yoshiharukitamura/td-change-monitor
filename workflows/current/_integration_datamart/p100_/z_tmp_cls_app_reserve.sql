select
  user_pseudo_id
  , ga_session_id
  , event_name
  , reservation_id_key as reservation_id
  , max(event_unixtime) as event_unixtime
  , max(event_timestamp) as event_timestamp
  , max(time) as time
from
  _integration_datamart.z_tmp_cls_app_log_104w
  inner join (
      select
        reservation_id as reservation_id_key
        , min(event_timestamp) as event_timestamp_reserve
        , min_by(user_pseudo_id, event_timestamp) as user_pseudo_id
        , min_by(ga_session_id, event_timestamp) as ga_session_id
      from
        _integration_datamart.z_tmp_cls_app_log_104w
      where
        reservation_id is not null
      group by
        reservation_id
    ) using (user_pseudo_id, ga_session_id)
where
  event_name = 'g1_click_reserve_s3'
  and event_timestamp <= event_timestamp_reserve
group by
  user_pseudo_id
  , ga_session_id
  , event_name
  , reservation_id_key