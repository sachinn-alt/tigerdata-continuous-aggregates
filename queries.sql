-- ============================================================================
-- Tiger Data / TimescaleDB Continuous Aggregates (CAGGs) - Queries & Benchmarks
-- ============================================================================

-- 1. Populate Sample Telemetry Data (Generates 500,000 readings across 5 devices)
INSERT INTO device_metrics (time, device_id, datacenter_id, cpu_usage, memory_usage, temperature, power_consumption_watts)
SELECT
    ts AS time,
    'sensor-' || LPAD((1 + (RANDOM() * 4)::int)::text, 3, '0') AS device_id,
    'dc-us-east' AS datacenter_id,
    ROUND((20 + (RANDOM() * 75))::numeric, 2) AS cpu_usage,
    ROUND((40 + (RANDOM() * 50))::numeric, 2) AS memory_usage,
    ROUND((35 + (RANDOM() * 45))::numeric, 2) AS temperature,
    ROUND((150 + (RANDOM() * 300))::numeric, 2) AS power_consumption_watts
FROM GENERATE_SERIES(
    NOW() - INTERVAL '7 days',
    NOW(),
    INTERVAL '10 seconds'
) AS ts;

-- Manually refresh the CAGG for historical data (if testing immediately)
CALL refresh_continuous_aggregate('device_metrics_hourly', NOW() - INTERVAL '7 days', NOW());


-- ----------------------------------------------------------------------------
-- BENCHMARK 1: Dashboard Query on Raw Hypertable (Slow / High CPU)
-- Scans millions of high-frequency rows and calculates aggregations on the fly.
-- ----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    time_bucket('1 hour', time) AS bucket,
    device_id,
    AVG(cpu_usage) AS avg_cpu,
    MIN(temperature) AS min_temp,
    MAX(temperature) AS max_temp,
    SUM(power_consumption_watts) AS total_power
FROM device_metrics
WHERE device_id = 'sensor-001'
  AND time >= NOW() - INTERVAL '7 days'
GROUP BY bucket, device_id
ORDER BY bucket DESC;


-- ----------------------------------------------------------------------------
-- BENCHMARK 2: Dashboard Query on Continuous Aggregate (Lightning-Fast)
-- Reads pre-materialized hourly summaries directly from the underlying hypertable.
-- ----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    bucket,
    device_id,
    avg_cpu_usage,
    min_temperature,
    max_temperature,
    total_power_watts,
    reading_count
FROM device_metrics_hourly
WHERE device_id = 'sensor-001'
  AND bucket >= NOW() - INTERVAL '7 days'
ORDER BY bucket DESC;


-- ----------------------------------------------------------------------------
-- 3. Advanced Multi-Tier Rollup: Daily Summary from Hourly CAGG
-- CAGGs can be aggregated further with zero overhead for long-term analytics
-- ----------------------------------------------------------------------------
SELECT
    time_bucket('1 day', bucket) AS day,
    device_id,
    ROUND(AVG(avg_cpu_usage)::numeric, 2) AS daily_avg_cpu,
    MIN(min_temperature) AS daily_min_temp,
    MAX(max_temperature) AS daily_max_temp,
    ROUND(SUM(total_power_watts)::numeric, 2) AS daily_total_power_watts,
    SUM(reading_count) AS total_readings
FROM device_metrics_hourly
WHERE bucket >= NOW() - INTERVAL '30 days'
GROUP BY day, device_id
ORDER BY day DESC;
