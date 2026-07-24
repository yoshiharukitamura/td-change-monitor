-- [TD TRACING] CDP: Audience
-- CDP: Audience: audience/create_empty_table_udp.sql
-- console link: ${link}
-- workflow link: ${td_console_endpoint}/app/workflows/sessions/${session_id}
-- workflow task: ${task_name}
-- Create empty table with UDP property
DROP TABLE IF EXISTS ${table_name};
CREATE TABLE ${table_name} (${join_column_name} VARCHAR)
  WITH (bucketed_on = array['${join_column_name}'], bucket_count = ${bucket_count});
