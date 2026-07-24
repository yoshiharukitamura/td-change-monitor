select distinct
  audience_id
from
  ${ps.wf_logging}
where
  session_uuid = '${session_uuid}'
  and regexp_like(audience_id, '^\d+$')