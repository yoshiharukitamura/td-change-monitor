-- set session join_distribution_type = 'PARTITIONED'

WITH
P_01 AS
(
SELECT
  id
  , MAX(modified) AS modified
FROM
  l0_web_reservation_production.reservation_persons
GROUP BY
  id
)

SELECT
  DISTINCT
  TD_TIME_PARSE(P_02.modified, 'JST') AS time
  , P_02.id
  , member_type
  , member_card_no
  , name
  , birthday
  , gender
  , phone
  , zip_code1
  , zip_code2
  , email
  , password
  , send_news_mail
  , created
  , P_02.modified
  , deleted
  , deleted_date
FROM
  l0_web_reservation_production.reservation_persons AS P_02
JOIN
  P_01 ON P_01.id = P_02.id AND P_01.modified = P_02.modified
