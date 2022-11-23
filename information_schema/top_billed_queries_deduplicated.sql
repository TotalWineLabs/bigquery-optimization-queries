-- This query will return the top billed queries ordered by most costly to least costly over the specified timeframe.
-- Note that this version of the query will deduplicate on the query itself thus will take more time to process and potentially
-- scanning more data than the non-deduplicated version.
-- Note that these calculations are assuming an on-demand billing model.

-- Change this value to change how far in the past the query will search
DECLARE interval_in_days INT64 DEFAULT 14;

BEGIN
    WITH src AS (
      SELECT
        user_email AS user,
        query,
        job_id AS jobId,
        project_id AS projectId,
        start_time AS startTime,
        end_time AS endTime,
        ROUND(COALESCE(total_bytes_billed,
            0), 2) AS totalBytesBilled,
        ROUND(COALESCE(total_bytes_billed,
            0) / 1000000, 2) AS totalMegabytesBilled,
        ROUND(COALESCE(total_bytes_billed,
            0) / 1000000000, 2) AS totalGigabytesBilled,
        ROUND(COALESCE(total_bytes_billed,
            0) / 1000000000000, 2) AS totalTerabytesBilled,
        ROUND(SAFE_DIVIDE(total_bytes_billed,
            102400000000) * 5, 2) AS cost,
        ROUND(SAFE_DIVIDE(total_slot_ms,
            TIMESTAMP_DIFF(end_time, start_time, MILLISECOND)), 2) AS approximateSlotCount,
        ROW_NUMBER() OVER(PARTITION BY job_id ORDER BY end_time DESC) AS _rnk,
        ROW_NUMBER() OVER(PARTITION BY query ORDER BY total_bytes_billed DESC) AS _queryRank
      FROM
        `<project-name>`.`<dataset-region>`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
      WHERE
        creation_time BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL interval_in_days DAY)
        AND CURRENT_TIMESTAMP()
        AND job_type = "QUERY"
        AND total_slot_ms IS NOT NULL
        AND state = "DONE" ),
    jobsDeduplicated AS (
      SELECT
        * EXCEPT(_rnk)
      FROM
        src
      WHERE
        _rnk = 1
    ),
    queriesDeduplicated AS (
      SELECT
        * EXCEPT(_queryRank)
      FROM
        jobsDeduplicated
      WHERE _queryRank = 1
    )

SELECT
  *
FROM
  queriesDeduplicated
ORDER BY
  cost DESC;
END