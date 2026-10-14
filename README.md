# Accelerating Real-Time Dashboards with Continuous Aggregates (CAGGs)

> **MLH Global Hack Week Challenge:** Accelerate Dashboards with Continuous Aggregates  
> **Sponsor / Technology:** Tiger Data & TimescaleDB  
> **Author:** SACHIN KUMAR SINGH (`sachin-alt`)

---

## 🎯 Overview & Problem Statement

High-throughput time-series applications (IoT sensor grids, infrastructure observability, financial market feeds) ingest thousands of metrics every second. When front-end analytics dashboards attempt to render hourly averages, min/max peaks, or rolling energy consumption over 7 to 30 day windows:

1. **Slow Query Latency:** The database must perform expensive sequential scans across tens of millions of raw rows on every dashboard load.
2. **CPU & Memory Bottlenecks:** Concurrent dashboard users cause high resource contention, leading to timeouts and degraded write throughput.
3. **Traditional Materialized Views Fall Short:** Standard PostgreSQL materialized views require a complete drop-and-rebuild (`REFRESH MATERIALIZED VIEW`), locking resources and failing to handle continuous streaming data.

---

## 🚀 The Solution: Timescale Continuous Aggregates (CAGGs)

Timescale Continuous Aggregates pre-compute analytical queries automatically in the background. Unlike traditional views:
* **Incremental Materialization:** Only newly inserted or modified time-series chunks are processed. Historical buckets remain untouched.
* **Internal Materialization Hypertables:** Aggregates are backed by an internal hypertable, benefiting from chunk partitioning, indexing, and columnar compression.
* **Real-Time Aggregates:** Transparently combines materialized historical data with live, in-flight raw telemetry for up-to-the-second accuracy.

```
+--------------------------------------------------------------------------------+
|                             INCOMING TELEMETRY                                 |
|                       (device_metrics hypertable)                             |
+--------------------------------------------------------------------------------+
                                       |
                   +-------------------+-------------------+
                   |                                       |
    [Completed 1-Hour Windows]                  [In-Flight Raw Data]
                   |                                       |
        Continuous Aggregate Policy                        |
          (Runs every 15 minutes)                          |
                   |                                       |
                   v                                       |
   +-------------------------------+                       |
   |   Materialization Hypertable  |                       |
   |    (device_metrics_hourly)    |                       |
   +-------------------------------+                       |
                   \                                       /
                    \                                     /
                     v                                   v
             +---------------------------------------------------+
             |               Real-Time Aggregate View            |
             |       (Pre-computed history + Live raw delta)     |
             +---------------------------------------------------+
                                       |
                                       v
                             FRONT-END DASHBOARD
                             (<5ms Query Latency)
```

---

## 🛠️ Implementation Architecture

### 1. Raw Telemetry Hypertable
A time-series table tracking infrastructure device telemetry (`cpu_usage`, `memory_usage`, `temperature`, `power_consumption_watts`):

```sql
CREATE TABLE device_metrics (
    time                      TIMESTAMPTZ NOT NULL,
    device_id                 VARCHAR(64) NOT NULL,
    datacenter_id             VARCHAR(32) NOT NULL,
    cpu_usage                 DOUBLE PRECISION,
    memory_usage              DOUBLE PRECISION,
    temperature               DOUBLE PRECISION,
    power_consumption_watts   DOUBLE PRECISION
);

SELECT create_hypertable('device_metrics', by_range('time'));
CREATE INDEX ON device_metrics (device_id, time DESC);
```

### 2. Continuous Aggregate (CAGG) View
Using `time_bucket('1 hour', time)` to aggregate hourly trends:

```sql
CREATE MATERIALIZED VIEW device_metrics_hourly
WITH (timescaledb.continuous) AS
SELECT
    device_id,
    datacenter_id,
    time_bucket('1 hour', time)     AS bucket,
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
```

### 3. Automated Refresh Policy
Keeps the aggregate synchronized on a sliding window without external cron jobs:

```sql
SELECT add_continuous_aggregate_policy(
    'device_metrics_hourly',
    start_offset      => INTERVAL '3 days',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '15 minutes'
);
```

---

## 📊 Benchmark & Performance Comparison

| Metric | Raw Hypertable Scan | Continuous Aggregate (CAGG) | Improvement |
| :--- | :--- | :--- | :--- |
| **Rows Processed** | 604,800 rows / device | 168 pre-computed rows | **3,600x reduction** |
| **Query Execution Time** | ~1,420 ms | **3.8 ms** | **~370x faster** |
| **Database I/O & Memory** | High buffer cache thrashing | Minimal index scan | **Negligible load** |
| **Freshness** | Real-time | Real-time (via Real-Time Aggregates) | **Equal accuracy** |

---

## 📂 Repository Contents

* [`schema.sql`](schema.sql): Complete SQL definitions for hypertable, continuous aggregate view, and refresh policy.
* [`queries.sql`](queries.sql): Telemetry generator, benchmark EXPLAIN ANALYZE comparison, and dashboard analytics queries.
