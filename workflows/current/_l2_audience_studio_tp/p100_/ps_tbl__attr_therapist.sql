select
  therapist_no as mstr__id
  , therapist_no
  , therapist_id
  , therapist_name
  , professional_name
  , division
  , gender
  , age
  , zip_code
  , pref_name
  , area_name
  , old_therapist_id
  , introducer_therapist_id
  , contract_type
  , td_time_parse(first_entry_date) as first_entry_datetime
  , hope_property_id_1
  , hope_property_id_2
  , work_saturday
  , work_sunday
  , work_holiday
  , week_days
  , timezone
  , min_applicant_reqenst
  , avg_applicant_reqenst
  , max_applicant_reqenst
  , max_nuturing_reqenst
  , email
  , tel01
  , tel02
  , tel03
from
  _integration_datamart.mst_therapist
