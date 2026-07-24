select
  ${td.last_results.cols.join(', ')}
from
  ${sheet}
where
  col_a != 'therapist_no'