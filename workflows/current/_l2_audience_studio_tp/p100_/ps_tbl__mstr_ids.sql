select
  therapist_no as mstr__id
  , substr(lower(to_hex(sha256(to_utf8(cast(therapist_no as varchar))))), 1, 1) as hash_digit
from
  _integration_datamart.mst_therapist