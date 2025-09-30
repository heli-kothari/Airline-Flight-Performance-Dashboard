-- ============================================
-- ADVANCED SQL QUERIES FOR FLIGHT ANALYSIS
-- ============================================

-- Query 1: Top 10 Routes with Most Delays by Time of Day
-- Shows which routes are most problematic during different hours
SELECT 
    origin || ' → ' || dest as route,
    CASE 
        WHEN EXTRACT(HOUR FROM scheduled_dep_time) BETWEEN 5 AND 11 THEN 'Morning (5-11)'
        WHEN EXTRACT(HOUR FROM scheduled_dep_time) BETWEEN 12 AND 17 THEN 'Afternoon (12-17)'
        ELSE 'Evening (18-23)'
    END as time_period,
    COUNT(*) as total_flights,
    AVG(dep_delay) as avg_delay,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY dep_delay) as percentile_75_delay
FROM flights
WHERE dep_delay > 15
GROUP BY origin, dest, time_period
HAVING COUNT(*) > 50
ORDER BY avg_delay DESC
LIMIT 10;

-- Query 2: Monthly Trend Analysis with Year-over-Year Comparison
-- Identifies seasonal patterns and year-over-year improvements/degradations
WITH monthly_stats AS (
    SELECT 
        airline,
        EXTRACT(YEAR FROM flight_date) as year,
        EXTRACT(MONTH FROM flight_date) as month,
        COUNT(*) as total_flights,
        AVG(dep_delay) as avg_delay,
        COUNT(CASE WHEN cancelled = 1 THEN 1 END) * 100.0 / COUNT(*) as cancel_rate
    FROM flights
    GROUP BY airline, year, month
)
SELECT 
    airline,
    year,
    month,
    total_flights,
    ROUND(avg_delay::numeric, 2) as avg_delay,
    ROUND(cancel_rate::numeric, 2) as cancel_rate,
    LAG(avg_delay) OVER (PARTITION BY airline, month ORDER BY year) as prev_year_delay,
    ROUND((avg_delay - LAG(avg_delay) OVER (PARTITION BY airline, month ORDER BY year))::numeric, 2) as yoy_change
FROM monthly_stats
ORDER BY airline, year, month;

-- Query 3: Delay Cascade Effect Analysis
-- Identifies how initial delays compound throughout the day
WITH flight_sequence AS (
    SELECT 
        airline,
        DATE(flight_date) as day,
        scheduled_dep_time,
        dep_delay,
        late_aircraft_delay,
        ROW_NUMBER() OVER (PARTITION BY airline, DATE(flight_date) ORDER BY scheduled_dep_time) as flight_seq
    FROM flights
    WHERE cancelled = 0
)
SELECT 
    airline,
    flight_seq,
    COUNT(*) as flights_in_sequence,
    AVG(dep_delay) as avg_delay,
    AVG(late_aircraft_delay) as avg_late_aircraft_delay,
    CORR(flight_seq, dep_delay) as correlation_seq_delay
FROM flight_sequence
WHERE flight_seq <= 20
GROUP BY airline, flight_seq
ORDER BY airline, flight_seq;

-- Query 4: Weather Impact by Geographic Region
-- Analyzes weather delays by airport clusters/regions
WITH airport_weather AS (
    SELECT 
        origin,
        COUNT(*) as total_flights,
        SUM(weather_delay) as total_weather_delay,
        AVG(weather_delay) as avg_weather_delay,
        COUNT(CASE WHEN weather_delay > 0 THEN 1 END) as weather_affected
    FROM flights
    GROUP BY origin
)
SELECT 
    ap.state,
    COUNT(DISTINCT aw.origin) as airports_in_state,
    SUM(aw.total_flights) as total_flights,
    SUM(aw.total_weather_delay) as total_weather_delay,
    AVG(aw.avg_weather_delay) as avg_weather_delay_per_airport,
    SUM(aw.weather_affected) * 100.0 / SUM(aw.total_flights) as weather_impact_pct
FROM airport_weather aw
JOIN airports ap ON aw.origin = ap.airport_code
GROUP BY ap.state
HAVING SUM(aw.total_flights) > 1000
ORDER BY weather_impact_pct DESC;

-- Query 5: Airline Performance Score (Composite Metric)
-- Creates a comprehensive performance score based on multiple factors
WITH airline_metrics AS (
    SELECT 
        airline,
        COUNT(*) as total_flights,
        AVG(dep_delay) as avg_delay,
        STDDEV(dep_delay) as delay_variability,
        COUNT(CASE WHEN dep_delay <= 15 THEN 1 END) * 100.0 / COUNT(*) as on_time_pct,
        COUNT(CASE WHEN cancelled = 1 THEN 1 END) * 100.0 / COUNT(*) as cancel_pct,
        AVG(CASE WHEN dep_delay > 0 THEN dep_delay END) as avg_positive_delay
    FROM flights
    GROUP BY airline
    HAVING COUNT(*) > 1000
)
SELECT 
    a.airline_name,
    am.total_flights,
    ROUND(am.avg_delay::numeric, 2) as avg_delay,
    ROUND(am.on_time_pct::numeric, 2) as on_time_pct,
    ROUND(am.cancel_pct::numeric, 2) as cancel_pct,
    -- Composite performance score (higher is better)
    ROUND((
        (am.on_time_pct * 0.4) + 
        ((100 - LEAST(am.cancel_pct * 10, 100)) * 0.3) +
        ((100 - LEAST(am.avg_delay, 100)) * 0.3)
    )::numeric, 2) as performance_score,
    RANK() OVER (ORDER BY (
        (am.on_time_pct * 0.4) + 
        ((100 - LEAST(am.cancel_pct * 10, 100)) * 0.3) +
        ((100 - LEAST(am.avg_delay, 100)) * 0.3)
    ) DESC) as overall_rank
FROM airline_metrics am
JOIN airlines a ON am.airline = a.airline_code
ORDER BY performance_score DESC;

-- Query 6: Route Reliability Analysis
-- Identifies most reliable routes (consistent performance)
SELECT 
    origin || ' → ' || dest as route,
    COUNT(*) as total_flights,
    AVG(dep_delay) as avg_delay,
    STDDEV(dep_delay) as delay_std_dev,
    MIN(dep_delay) as min_delay,
    MAX(dep_delay) as max_delay,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY dep_delay) as q1_delay,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dep_delay) as median_delay,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY dep_delay) as q3_delay,
    -- Reliability score (lower is better - consistent performance)
    ROUND((STDDEV(dep_delay) / NULLIF(AVG(ABS(dep_delay)), 0))::numeric, 3) as coefficient_variation
FROM flights
WHERE cancelled = 0
GROUP BY origin, dest
HAVING COUNT(*) > 100
ORDER BY coefficient_variation ASC
LIMIT 20;

-- Query 7: Delay Type Distribution by Airline
-- Shows breakdown of delay causes for each airline
SELECT 
    a.airline_name,
    COUNT(*) as total_delayed_flights,
    SUM(carrier_delay) as total_carrier_delay,
    SUM(weather_delay) as total_weather_delay,
    SUM(nas_delay) as total_nas_delay,
    SUM(security_delay) as total_security_delay,
    SUM(late_aircraft_delay) as total_late_aircraft_delay,
    -- Percentages
    ROUND((SUM(carrier_delay) * 100.0 / NULLIF(SUM(dep_delay), 0))::numeric, 1) as carrier_pct,
    ROUND((SUM(weather_delay) * 100.0 / NULLIF(SUM(dep_delay), 0))::numeric, 1) as weather_pct,
    ROUND((SUM(nas_delay) * 100.0 / NULLIF(SUM(dep_delay), 0))::numeric, 1) as nas_pct,
    ROUND((SUM(security_delay) * 100.0 / NULLIF(SUM(dep_delay), 0))::numeric, 1) as security_pct,
    ROUND((SUM(late_aircraft_delay) * 100.0 / NULLIF(SUM(dep_delay), 0))::numeric, 1) as late_aircraft_pct
FROM flights f
JOIN airlines a ON f.airline = a.airline_code
WHERE dep_delay > 15
GROUP BY a.airline_name
ORDER BY total_delayed_flights DESC;

-- Query 8: Hub Airport Analysis
-- Identifies hub airports and their operational characteristics
WITH hub_metrics AS (
    SELECT 
        origin as airport,
        COUNT(*) as departures,
        AVG(dep_delay) as avg_dep_delay,
        COUNT(DISTINCT dest) as unique_destinations,
        COUNT(DISTINCT airline) as airlines_operating
    FROM flights
    GROUP BY origin
),
arrival_metrics AS (
    SELECT 
        dest as airport,
        COUNT(*) as arrivals,
        AVG(arr_delay) as avg_arr_delay
    FROM flights
    GROUP BY dest
)
SELECT 
    ap.airport_code,
    ap.airport_name,
    ap.city,
    hm.departures + COALESCE(am.arrivals, 0) as total_operations,
    hm.departures,
    am.arrivals,
    hm.unique_destinations,
    hm.airlines_operating,
    ROUND(hm.avg_dep_delay::numeric, 2) as avg_dep_delay,
    ROUND(am.avg_arr_delay::numeric, 2) as avg_arr_delay,
    CASE 
        WHEN hm.unique_destinations > 50 AND hm.airlines_operating > 5 THEN 'Major Hub'
        WHEN hm.unique_destinations > 25 THEN 'Regional Hub'
        ELSE 'Standard Airport'
    END as hub_classification
FROM hub_metrics hm
JOIN airports ap ON hm.airport = ap.airport_code
LEFT JOIN arrival_metrics am ON hm.airport = am.airport
ORDER BY total_operations DESC
LIMIT 20;

-- Query 9: Day of Week Performance Pattern
-- Identifies which days have best/worst performance
SELECT 
    CASE EXTRACT(DOW FROM flight_date)
        WHEN 0 THEN 'Sunday'
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
    END as day_of_week,
    EXTRACT(DOW FROM flight_date) as dow_num,
    COUNT(*) as total_flights,
    AVG(dep_delay) as avg_delay,
    COUNT(CASE WHEN dep_delay > 15 THEN 1 END) * 100.0 / COUNT(*) as delay_pct,
    COUNT(CASE WHEN cancelled = 1 THEN 1 END) * 100.0 / COUNT(*) as cancel_pct,
    ROUND(AVG(distance)::numeric, 0) as avg_distance
FROM flights
GROUP BY dow_num
ORDER BY dow_num;

-- Query 10: Predictive Delay Risk Score
-- Calculates risk factors for delays based on historical patterns
WITH route_history AS (
    SELECT 
        origin,
        dest,
        airline,
        AVG(dep_delay) as historical_avg_delay,
        COUNT(CASE WHEN dep_delay > 30 THEN 1 END) * 100.0 / COUNT(*) as severe_delay_rate,
        AVG(weather_delay) as avg_weather_impact
    FROM flights
    WHERE flight_date >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY origin, dest, airline
)
SELECT 
    rh.airline,
    rh.origin || ' → ' || rh.dest as route,
    ROUND(rh.historical_avg_delay::numeric, 2) as avg_historical_delay,
    ROUND(rh.severe_delay_rate::numeric, 2) as severe_delay_rate,
    ROUND(rh.avg_weather_impact::numeric, 2) as weather_risk,
    -- Risk score (0-100, higher means higher risk)
    ROUND((
        (LEAST(rh.historical_avg_delay, 60) / 60 * 40) +
        (rh.severe_delay_rate * 0.4) +
        (LEAST(rh.avg_weather_impact, 30) / 30 * 20)
    )::numeric, 2) as delay_risk_score,
    CASE 
        WHEN (
            (LEAST(rh.historical_avg_delay, 60) / 60 * 40) +
            (rh.severe_delay_rate * 0.4) +
            (LEAST(rh.avg_weather_impact, 30) / 30 * 20)
        ) > 60 THEN 'High Risk'
        WHEN (
            (LEAST(rh.historical_avg_delay, 60) / 60 * 40) +
            (rh.severe_delay_rate * 0.4) +
            (LEAST(rh.avg_weather_impact, 30) / 30 * 20)
        ) > 30 THEN 'Moderate Risk'
        ELSE 'Low Risk'
    END as risk_category
FROM route_history rh
ORDER BY delay_risk_score DESC
LIMIT 50;

-- Query 11: Airport Congestion Analysis
-- Identifies peak congestion times at major airports
SELECT 
    origin as airport,
    EXTRACT(HOUR FROM scheduled_dep_time) as departure_hour,
    COUNT(*) as scheduled_departures,
    AVG(dep_delay) as avg_delay,
    COUNT(CASE WHEN dep_delay > 30 THEN 1 END) as severe_delays,
    -- Congestion indicator
    CASE 
        WHEN COUNT(*) > 100 AND AVG(dep_delay) > 30 THEN 'High Congestion'
        WHEN COUNT(*) > 50 AND AVG(dep_delay) > 15 THEN 'Moderate Congestion'
        ELSE 'Normal'
    END as congestion_level
FROM flights
WHERE scheduled_dep_time IS NOT NULL
GROUP BY origin, departure_hour
HAVING COUNT(*) > 20
ORDER BY origin, departure_hour;

-- Query 12: Cancellation Pattern Analysis
-- Analyzes cancellation patterns by various factors
SELECT 
    cancellation_code,
    CASE cancellation_code
        WHEN 'A' THEN 'Carrier'
        WHEN 'B' THEN 'Weather'
        WHEN 'C' THEN 'NAS'
        WHEN 'D' THEN 'Security'
        ELSE 'Unknown'
    END as cancellation_reason,
    COUNT(*) as total_cancellations,
    ROUND((COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ())::numeric, 2) as percentage,
    -- Most affected routes
    MODE() WITHIN GROUP (ORDER BY origin || ' → ' || dest) as most_affected_route,
    -- Most affected airline
    MODE() WITHIN GROUP (ORDER BY airline) as most_affected_airline
FROM flights
WHERE cancelled = 1
GROUP BY cancellation_code
ORDER BY total_cancellations DESC;
