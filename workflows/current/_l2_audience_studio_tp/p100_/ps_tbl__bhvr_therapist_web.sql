select
  time
  , therapistno as mstr__id
  , time as web_access_datetime
  , td_url as web_access_page
from
  l0_website_access.pv_log_therapist
where
  time >= td_time_parse('2024-01-01', 'jst')