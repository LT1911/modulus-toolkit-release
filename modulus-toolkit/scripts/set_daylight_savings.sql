INSERT INTO AS_BASE.DAYLIGHT_SAVINGS
  (DAYLIGHT_SAVING_ID, TIMEZONE_ID, VALID_FROM_UTC, VALID_TILL_UTC, OFFSET)
WITH last_end AS (
  SELECT MAX(VALID_TILL_UTC) AS last_valid_till
  FROM   AS_BASE.DAYLIGHT_SAVINGS
  WHERE  TIMEZONE_ID IS NULL          -- match your existing rows; adjust if needed
),
start_year AS (
  SELECT GREATEST(
           2025,
           NVL(EXTRACT(YEAR FROM last_valid_till) + 1, 2025)
         ) AS y_start
  FROM   last_end
),
years AS (
  SELECT y_start + LEVEL - 1 AS y
  FROM   start_year
  CONNECT BY LEVEL <= GREATEST(0, 2050 - y_start + 1)  -- yields 0 rows if y_start > 2050
),
edges AS (
  SELECT
    y,
    /* your logic: last Sunday in March + 2 hours */
    CAST(
      TRUNC(LAST_DAY(TO_DATE(y||'-03-01','YYYY-MM-DD')), 'IW') + 6
      + NUMTODSINTERVAL(2,'HOUR')
      AS TIMESTAMP
    ) AS dst_start_utc,
    /* your logic: last Sunday in October + 3 hours */
    CAST(
      TRUNC(LAST_DAY(TO_DATE(y||'-10-01','YYYY-MM-DD')), 'IW') + 6
      + NUMTODSINTERVAL(3,'HOUR')
      AS TIMESTAMP
    ) AS dst_end_utc
  FROM years
),
-- avoid inserting duplicates if some future rows already exist
todo AS (
  SELECT e.*
  FROM   edges e
  WHERE  NOT EXISTS (
           SELECT 1
           FROM   AS_BASE.DAYLIGHT_SAVINGS d
           WHERE  d.TIMEZONE_ID     IS NULL
           AND    d.VALID_FROM_UTC  = e.dst_start_utc
           AND    d.VALID_TILL_UTC  = e.dst_end_utc
         )
),
base_id AS (
  SELECT NVL(MAX(DAYLIGHT_SAVING_ID),0) AS base
  FROM   AS_BASE.DAYLIGHT_SAVINGS
)
SELECT
  base_id.base + ROW_NUMBER() OVER (ORDER BY t.y) AS DAYLIGHT_SAVING_ID,
  NULL                                            AS TIMEZONE_ID,
  t.dst_start_utc                                 AS VALID_FROM_UTC,
  t.dst_end_utc                                   AS VALID_TILL_UTC,
  60                                              AS OFFSET
FROM todo t
CROSS JOIN base_id;
exit;