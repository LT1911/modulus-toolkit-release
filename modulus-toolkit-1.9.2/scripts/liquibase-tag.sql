SET HEADING OFF;
SET FEEDBACK OFF;

WITH RankedChangelogs AS (
    SELECT
        id,
        tag,
        orderexecuted,
        ROW_NUMBER() OVER (
            PARTITION BY tag
            ORDER BY orderexecuted DESC
        ) as rn
    FROM
        system.databasechangelog
    WHERE
        tag IS NOT NULL
)
SELECT
    id
FROM
    RankedChangelogs
WHERE
    rn = 1
ORDER BY
    orderexecuted DESC;

--to get back to PS scope:
exit;