-- ============================================================================
-- Tiger Data / TimescaleDB Continuous Aggregates (CAGGs) Implementation
-- Challenge: Accelerate Dashboards with Continuous Aggregates (MLH Global Hack Week)
-- ============================================================================

-- 1. Enable TimescaleDB Extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- 2. Create the Raw Metrics Hypertable
-- Scenario: High-frequency IoT / Infrastructure telemetry reporting every second.
DROP TABLE IF EXISTS device_metrics CASCADE;

CREATE TABLE device_metrics (
    time                      TIMESTAMPTZ NOT NULL,
    device_id                 VARCHAR(64) NOT NULL,
    datacenter_id             VARCHAR(32) NOT NULL,
    cpu_usage                 DOUBLE PRECISION,
    memory_usage              DOUBLE PRECISION,
    temperature               DOUBLE PRECISION,
    power_consumption_watts   DOUBLE PRECISION
);

-- Convert standard PostgreSQL table into a Timescale hypertable partitioned by time
SELECT create_hypertable(
    'device_metrics',
    by_range('time'),
    if_not_exists => TRUE
);

-- Create index on device_id and time for fast filtering
CREATE INDEX IF NOT EXISTS idx_device_metrics_device_time 
ON device_metrics (device_id, time DESC);

-- 3. Create Continuous Aggregate (CAGG) for Hourly Dashboard Rollups
-- Pre-computes hourly averages, rolling power consumption, and min/max temperatures
DROP MATERIALIZED VIEW IF EXISTS device_metrics_hourly CASCADE;

CREATE MATERIALIZED VIEW device_metrics_hourly
WITH (timescaledb.continuous) AS
SELECT
    device_id,
    datacenter_id,
    time_bucket('1 hour', time) AS bucket,
    AVG(cpu_usage)                  AS avg_cpu_usage,
    MAX(cpu_usage)                  AS max_cpu_usage,
    AVG(memory_usage)               AS avg_memory_usage,
    MIN(temperature)                AS min_temperature,
    MAX(temperature)                AS max_temperature,
    AVG(temperature)                AS avg_temperature,
    SUM(power_consumption_watts)    AS total_power_watts,
    COUNT(*)                        AS reading_count
FROM device_metrics
GROUP BY device_id, datacenter_id, bucket
WITH NO DATA;

-- 4. Configure Automated Background Refresh Policy
-- The database background worker will automatically refresh older buckets incrementally
SELECT add_continuous_aggregate_policy(
    'device_metrics_hourly',
    start_offset      => INTERVAL '3 days',   -- re-aggregate up to 3 days back to capture late arrivals
    end_offset        => INTERVAL '1 hour',   -- stop 1 hour before current time (latest raw data is handled in real-time)
    schedule_interval => INTERVAL '15 minutes' -- execute the background worker every 15 minutes
);

-- 5. Enable Real-Time Aggregation (Default in TimescaleDB)
-- Ensures dashboard queries seamlessly combine pre-computed materialized historical
-- buckets with the newest in-flight raw data from the hypertable.
ALTER MATERIALIZED VIEW device_metrics_hourly SET (timescaledb.materialized_only = false);
