-- SELECT 'CREATE DATABASE dockerdb'
-- WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'dockerdb')\gexec
CREATE TABLE IF NOT EXISTS events_raw(
  event_type text,
  id text PRIMARY KEY,
  metadata text,
  time_created timestamptz,
  signature text UNIQUE,
  msg_id text,
  source text
);

CREATE TABLE IF NOT EXISTS events_enriched (
  events_raw_signature text PRIMARY KEY,
  enriched_metadata text,
  CONSTRAINT fk_event FOREIGN KEY(events_raw_signature) REFERENCES events_raw(signature)
);

-- EVENTS --------------------------------------------------
CREATE VIEW events AS
SELECT
  raw.id,
  raw.event_type,
  raw.time_created,
  raw.metadata,
  enr.enriched_metadata,
  raw.signature,
  raw.msg_id,
  raw.source
FROM
  events_raw AS raw
  LEFT JOIN events_enriched AS enr ON raw.signature = enr.events_raw_signature;

-- CHANGES --------------------------------------------------
CREATE VIEW changes AS
SELECT
  source,
  event_type,
  (commits ->> 'id') :: text as change_id,
  date_trunc('second', (commits ->> 'timestamp') :: timestamp) as time_created
FROM
  (
    SELECT
      *,
      json_array_elements(metadata :: json -> 'commits') as commits
    FROM
      events_raw
  ) s
WHERE
  event_type = 'push'
GROUP BY
  1,
  2,
  3,
  4;

-- DEPLOYMENTS --------------------------------------------------
CREATE VIEW deployments AS WITH deploys_cloudbuild_github_gitlab AS (
  SELECT
    source,
    id as deploy_id,
    time_created,
    CASE
      WHEN source like 'github%' then metadata :: json -> 'deployment' ->> 'sha'
      WHEN source like 'gitlab%' then COALESCE(
        --# Data structure from GitLab Pipelines
        metadata :: json -> 'commit' ->> 'id',
        --# Data structure from GitLab Deployments
        --# REGEX to get the commit sha from the URL
        substring(
          metadata :: json ->> 'commit_url'
          from
            '.*commit\/(.*)'
        )
      )
    END AS main_commit,
    CASE
      WHEN source like 'github%' then metadata :: json -> 'deployment' ->> 'additional_sha'
    END AS additional_commits
  FROM
    events_raw
  WHERE
    (
      --# GitHub Deployments
      (
        source LIKE 'github%'
        and event_type = 'deployment_status'
        and metadata :: json -> 'deployment_status' ->> 'state' = 'success'
      ) --# GitLab Pipelines
      OR (
        source LIKE 'gitlab%'
        AND event_type = 'pipeline'
        AND metadata :: json -> 'object_attributes' ->> 'status' = 'success'
      ) --# GitLab Deployments
      OR (
        source LIKE 'gitlab%'
        AND event_type = 'deployment'
        AND metadata :: json ->> 'status' = 'success'
      )
    )
),
deploys AS (
  SELECT
    *
  FROM
    deploys_cloudbuild_github_gitlab
),
changes_raw AS (
  SELECT
    id,
    metadata as change_metadata
  FROM
    events_raw
),
deployment_changes as (
  SELECT
    source,
    deploy_id,
    deploys.time_created time_created,
    change_metadata,
    change_metadata :: json -> 'commits' as array_commits,
    main_commit
  FROM
    deploys
    JOIN changes_raw on (
      changes_raw.id = deploys.main_commit -- TODO
      -- or changes_raw.id in unnest(deploys.additional_commits)
    )
)
SELECT
  source,
  deploy_id,
  time_created,
  main_commit,
  array_commits
FROM
  deployment_changes;

-- INCIDENTS --------------------------------------------------
CREATE VIEW incidents AS
SELECT
  source,
  incident_id,
  LEAST(
    MIN(
      CASE
        WHEN root.time_created < issue.time_created THEN root.time_created
        ELSE issue.time_created
      END
    ),
    MIN(issue.time_created),
    MIN(root.time_created)
  ) as time_created,
  MAX(time_resolved) as time_resolved,
  (array_agg(DISTINCT root_cause)) [1] as changes
FROM
  (
    SELECT
      source,
      CASE
        WHEN source LIKE 'github%' THEN metadata :: json -> 'issue' ->> 'number'
        WHEN source LIKE 'gitlab%'
        AND event_type = 'note' THEN metadata :: json -> 'object_attributes' ->> 'noteable_id'
        WHEN source LIKE 'gitlab%'
        AND event_type = 'issue' THEN metadata :: json -> 'object_attributes' ->> 'id'
        WHEN source LIKE 'pagerduty%' THEN metadata :: json -> 'event' -> 'data' ->> 'id'
      END AS incident_id,
      CASE
        WHEN source LIKE 'github%' THEN (metadata :: json -> 'issue' ->> 'created_at') :: timestamptz
        WHEN source LIKE 'gitlab%' THEN (
          metadata :: json -> 'object_attributes' ->> 'created_at'
        ) :: timestamptz
        WHEN source LIKE 'pagerduty%' THEN (metadata :: json -> 'event' ->> 'occurred_at') :: timestamptz
      END AS time_created,
      CASE
        WHEN source LIKE 'github%' THEN (metadata :: json -> 'issue' ->> 'closed_at') :: timestamptz
        WHEN source LIKE 'gitlab%' THEN (
          metadata :: json -> 'object_attributes' ->> 'closed_at'
        ) :: timestamptz
        WHEN source LIKE 'pagerduty%' THEN (metadata :: json -> 'event' ->> 'occurred_at') :: timestamptz
      END AS time_resolved,
      (
        regexp_matches(metadata, 'root cause: ([[:alnum:]]*)')
      ) [1] as root_cause,
      CASE
        WHEN source LIKE 'github%' THEN REPLACE(
          metadata :: json -> 'issue' ->> 'labels',
          ' ',
          ''
        ) ~ '"name":"Incident"'
        WHEN source LIKE 'gitlab%' THEN REPLACE(
          metadata :: json -> 'object_attributes' ->> 'labels',
          ' ',
          ''
        ) ~ '"title":"Incident"'
        WHEN source LIKE 'pagerduty%' THEN TRUE --# All Pager Duty events are incident-related
      END AS bug
    FROM
      events_raw
    WHERE
      event_type LIKE 'issue%'
      OR event_type LIKE 'incident%'
      OR (
        event_type = 'note'
        and metadata :: json ->> '$.object_attributes.noteable_type' = 'Issue'
      )
  ) issue
  LEFT JOIN (
    SELECT
      time_created,
      (change_obj ->> 'id') :: text as changes
    FROM
      (
        SELECT
          *,
          json_array_elements(array_commits :: json) as change_obj
        FROM
          deployments
      ) s
  ) root on root.changes = root_cause
GROUP BY
  1,
  2
HAVING
  max(bug :: int) >= 1;

-- DASHBOARD HELPER: Med. Time to Change --------------------------------------------------
CREATE VIEW helper_med_time_to_change AS
SELECT
  d.deploy_id,
  d.time_created AS deploy_time_created,
  date_trunc('day', d.time_created) AS day,
  CASE
    WHEN FLOOR(
      EXTRACT(
        EPOCH
        FROM
          (d.time_created - c.time_created)
      )
    ) / 60 > 0 THEN FLOOR(
      EXTRACT(
        EPOCH
        FROM
          (d.time_created - c.time_created)
      ) / 60
    )
    ELSE NULL
  END AS med_time_to_change -- Ignore automated pushes
FROM
  (
    SELECT
      *,
      json_array_elements(array_commits :: json) as change_obj
    FROM
      deployments
  ) d
  LEFT JOIN changes c ON (change_obj ->> 'id') :: text = c.change_id;

-- DASHBOARD HELPER: Med. Time to Restore --------------------------------------------------
CREATE VIEW helper_med_time_to_restore AS
SELECT
  date_trunc('day', time_created) AS day,
  FLOOR(
    EXTRACT(
      EPOCH
      FROM
        (time_resolved - time_created)
    ) / 3600
  ) AS med_time_to_restore
FROM
  incidents;

-- DASHBOARD: Daily Deployments --------------------------------------------------
CREATE VIEW deployment_frequency_trend AS
SELECT
  date_trunc('day', time_created) AS day,
  COUNT(distinct deploy_id) AS deployments
FROM
  deployments
GROUP BY
  day
ORDER BY
  day;

-- DASHBOARD: Daily Median Time to Restore Services --------------------------------------------------
CREATE VIEW time_to_restore_trend AS
SELECT
  day,
  PERCENTILE_CONT(0.5) WITHIN GROUP (
    ORDER BY
      med_time_to_restore
  ) as daily_med_time_to_restore
FROM
  helper_med_time_to_restore
GROUP BY
  day;

-- DASHBOARD: Daily Change Failure Rate --------------------------------------------------
CREATE VIEW change_failure_trend AS
SELECT
  date_trunc('day', d.time_created) as day,
  SUM(
    CASE
      WHEN incident_id IS NULL THEN 0
      ELSE 1
    END
  ) :: NUMERIC / COUNT(DISTINCT deploy_id) :: NUMERIC as change_fail_rate
FROM
  (
    SELECT
      *,
      json_array_elements(array_commits :: json) as change_obj
    FROM
      deployments
  ) d
  LEFT JOIN changes c ON (change_obj ->> 'id') :: text = c.change_id
  LEFT JOIN(
    SELECT
      incident_id,
      changes AS change,
      time_resolved
    FROM
      incidents
  ) i ON i.change = (change_obj ->> 'id') :: text
GROUP BY
  day;

-- DASHBOARD: Lead Time for Changes --------------------------------------------------
CREATE VIEW lead_time_trend AS
SELECT
  day,
  CASE
    WHEN median_time_to_change_minutes IS NOT NULL THEN median_time_to_change_minutes / 60
    ELSE 0
  END AS median_time_to_change
FROM
  (
    SELECT
      day,
      PERCENTILE_CONT(0.5) WITHIN GROUP(
        ORDER BY
          med_time_to_change
      ) AS median_time_to_change_minutes
    FROM
      (
        SELECT
          *
        FROM
          helper_med_time_to_change
      ) med_time_to_change_query
    GROUP BY
      day
    ORDER BY
      day
  ) s;

-- DASHBOARD SDO: Change Failure Rate - Calculating the bucket --------------------------------------------------
CREATE VIEW change_failure_number AS
SELECT
  sum(
    CASE
      WHEN i.incident_id IS NULL THEN 0
      ELSE 1
    END
  ) :: numeric / count(DISTINCT d.deploy_id) :: numeric AS change_fail_rate
FROM
  (
    SELECT
      deployments.source,
      deployments.deploy_id,
      deployments.time_created,
      deployments.main_commit,
      deployments.array_commits,
      json_array_elements(deployments.array_commits) AS change_obj
    FROM
      deployments
  ) d
  LEFT JOIN changes c ON (d.change_obj ->> 'id' :: text) = c.change_id
  LEFT JOIN (
    SELECT
      incidents.incident_id,
      incidents.changes AS change,
      incidents.time_resolved
    FROM
      incidents
  ) i ON i.change = (d.change_obj ->> 'id' :: text)
WHERE
  d.time_created > (CURRENT_DATE - '3 mons' :: interval);

CREATE VIEW change_failure_bucket AS
SELECT
  CASE
    WHEN change_fail_rate <= 0.15 THEN '0-15%'
    WHEN change_fail_rate < 0.46 THEN '16-45%'
    ELSE '46-60%'
  END AS change_fail_rate
FROM
  change_failure_number
LIMIT
  1;

-- DASHBOARD SDO: Daily Median Time to Restore Services - Calculating the bucket --------------------------------------------------
CREATE VIEW time_to_restore_number AS
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (
    ORDER BY
      FLOOR(
        EXTRACT(
          EPOCH
          FROM
            (time_resolved - time_created)
        ) / 3600
      )
  ) AS med_time_to_resolve
FROM
  incidents
WHERE
  time_created > NOW() - INTERVAL '3 MONTH';

CREATE VIEW time_to_restore_bucket AS
SELECT
  CASE
    WHEN med_time_to_resolve < 24 THEN 'One day'
    WHEN med_time_to_resolve < 168 THEN 'One week'
    WHEN med_time_to_resolve < 730 THEN 'One month'
    WHEN med_time_to_resolve < 730 * 6 THEN 'Six months'
    ELSE 'One year'
  END AS med_time_to_resolve
FROM
  time_to_restore_number
LIMIT
  1;

-- DASHBOARD SDO: Lead Time to Change - Calculating the bucket --------------------------------------------------
CREATE VIEW lead_time_number AS
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP(
    ORDER BY
      med_time_to_change
  ) AS median_time_to_change
FROM
  (
    SELECT
      *
    FROM
      helper_med_time_to_change
    WHERE
      deploy_time_created > (CURRENT_DATE - INTERVAL '3 months') -- Limit to 3 months
  ) med_time_to_change_query
WHERE
  med_time_to_change IS NOT NULL;

CREATE VIEW lead_time_bucket AS
SELECT
  CASE
    WHEN median_time_to_change < 24 * 60 THEN 'One day'
    WHEN median_time_to_change < 168 * 60 THEN 'One week'
    WHEN median_time_to_change < 730 * 60 THEN 'One month'
    WHEN median_time_to_change < 730 * 6 * 60 THEN 'Six months'
    ELSE 'One year'
  END AS lead_time_to_change
FROM
  lead_time_number;

-- DASHBOARD SDO: Table view - Deployment Frequency - Calculating the bucket  --------------------------------------------------
CREATE VIEW deployment_frequency_number AS WITH last_three_months AS (
  SELECT
    date_trunc(
      'day' :: text,
      day.day :: timestamp without time zone
    ) AS day
  FROM
    generate_series(
      now() - '3 mons' :: interval,
      now(),
      '1 day' :: interval
    ) day(day)
  WHERE
    day > (
      SELECT
        DATE_TRUNC('day', MIN(time_created))
      FROM
        events_raw
    )
)
SELECT
  -- If the median number of days per week is more than 3, then Daily
  CASE
    WHEN PERCENTILE_CONT(0.5) WITHIN GROUP(
      ORDER BY
        days_deployed
    ) >= 3 THEN true
    ELSE false
  END AS daily,
  -- If most weeks have a deployment, then Weekly
  CASE
    WHEN PERCENTILE_CONT(0.5) WITHIN GROUP(
      ORDER BY
        week_deployed
    ) >= 1 THEN true
    ELSE false
  END AS weekly,
  -- Count the number of deployments per month.
  monthly_deploys,
  week
FROM
  (
    SELECT
      *,
      sum(week_deployed) OVER (PARTITION BY DATE_TRUNC('month', week)) as monthly_deploys
    FROM
      (
        SELECT
          DATE_TRUNC('week', last_three_months.day) AS week,
          MAX(
            CASE
              WHEN deployments.day IS NOT NULL THEN 1
              ELSE 0
            END
          ) AS week_deployed,
          COUNT(DISTINCT deployments.day) AS days_deployed
        FROM
          last_three_months
          LEFT JOIN (
            SELECT
              DATE_TRUNC('day', time_created) AS day,
              deploy_id
            FROM
              deployments
          ) deployments ON deployments.day = last_three_months.day
        GROUP BY
          week
      ) subquery1
  ) subquery2
GROUP BY
  week,
  monthly_deploys;

CREATE VIEW deployment_frequency_bucket AS
SELECT
  CASE
    WHEN daily THEN 'Daily'
    WHEN weekly THEN 'Weekly'
    WHEN monthly_deploys > 0 THEN 'Monhly' -- If at least one per month, then Monthly
    -- TODO Verify / BigQuery WHEN PERCENTILE_CONT(monthly_deploys, 0.5) OVER () >= 1 THEN  "Monthly"
    ELSE 'Yearly'
  END AS deployment_frequency
FROM
  deployment_frequency_number
LIMIT
  1;