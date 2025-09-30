-- Create database
CREATE DATABASE flight_performance;

-- Connect to the database
\c flight_performance;

-- Create flights table
CREATE TABLE flights (
    flight_id SERIAL PRIMARY KEY,
    flight_date DATE NOT NULL,
    airline VARCHAR(50) NOT NULL,
    flight_number VARCHAR(20) NOT NULL,
    origin VARCHAR(5) NOT NULL,
    dest VARCHAR(5) NOT NULL,
    scheduled_dep_time TIME,
    actual_dep_time TIME,
    dep_delay INTEGER DEFAULT 0,
    scheduled_arr_time TIME,
    actual_arr_time TIME,
    arr_delay INTEGER DEFAULT 0,
    cancelled SMALLINT DEFAULT 0,
    cancellation_code VARCHAR(1),
    distance INTEGER,
    carrier_delay INTEGER DEFAULT 0,
    weather_delay INTEGER DEFAULT 0,
    nas_delay INTEGER DEFAULT 0,
    security_delay INTEGER DEFAULT 0,
    late_aircraft_delay INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better query performance
CREATE INDEX idx_flights_airline ON flights(airline);
CREATE INDEX idx_flights_origin ON flights(origin);
CREATE INDEX idx_flights_dest ON flights(dest);
CREATE INDEX idx_flights_date ON flights(flight_date);
CREATE INDEX idx_flights_route ON flights(origin, dest);
CREATE INDEX idx_flights_delay ON flights(dep_delay);
CREATE INDEX idx_flights_cancelled ON flights(cancelled);

-- Create airports reference table
CREATE TABLE airports (
    airport_code VARCHAR(5) PRIMARY KEY,
    airport_name VARCHAR(100),
    city VARCHAR(50),
    state VARCHAR(2),
    latitude DECIMAL(10, 6),
    longitude DECIMAL(10, 6)
);

-- Create airlines reference table
CREATE TABLE airlines (
    airline_code VARCHAR(10) PRIMARY KEY,
    airline_name VARCHAR(100),
    country VARCHAR(50)
);

-- Insert sample airlines
INSERT INTO airlines (airline_code, airline_name, country) VALUES
('AA', 'American Airlines', 'USA'),
('DL', 'Delta Air Lines', 'USA'),
('UA', 'United Airlines', 'USA'),
('WN', 'Southwest Airlines', 'USA'),
('B6', 'JetBlue Airways', 'USA'),
('AS', 'Alaska Airlines', 'USA'),
('NK', 'Spirit Airlines', 'USA'),
('F9', 'Frontier Airlines', 'USA');

-- Insert sample airports
INSERT INTO airports (airport_code, airport_name, city, state, latitude, longitude) VALUES
('JFK', 'John F Kennedy International', 'New York', 'NY', 40.6413, -73.7781),
('LAX', 'Los Angeles International', 'Los Angeles', 'CA', 33.9416, -118.4085),
('ORD', 'O''Hare International', 'Chicago', 'IL', 41.9742, -87.9073),
('DFW', 'Dallas/Fort Worth International', 'Dallas', 'TX', 32.8998, -97.0403),
('ATL', 'Hartsfield-Jackson Atlanta International', 'Atlanta', 'GA', 33.6407, -84.4277),
('DEN', 'Denver International', 'Denver', 'CO', 39.8561, -104.6737),
('SFO', 'San Francisco International', 'San Francisco', 'CA', 37.6213, -122.3790),
('SEA', 'Seattle-Tacoma International', 'Seattle', 'WA', 47.4502, -122.3088),
('LAS', 'Harry Reid International', 'Las Vegas', 'NV', 36.0840, -115.1537),
('MCO', 'Orlando International', 'Orlando', 'FL', 28.4312, -81.3081),
('MIA', 'Miami International', 'Miami', 'FL', 25.7959, -80.2870),
('BOS', 'Boston Logan International', 'Boston', 'MA', 42.3656, -71.0096),
('PHX', 'Phoenix Sky Harbor International', 'Phoenix', 'AZ', 33.4352, -112.0101),
('IAH', 'George Bush Intercontinental', 'Houston', 'TX', 29.9902, -95.3368);

-- Create view for delayed flights analysis
CREATE VIEW vw_delayed_flights AS
SELECT 
    f.flight_id,
    f.flight_date,
    a.airline_name,
    f.origin,
    f.dest,
    f.dep_delay,
    f.carrier_delay,
    f.weather_delay,
    f.nas_delay,
    f.security_delay,
    f.late_aircraft_delay,
    CASE 
        WHEN f.carrier_delay > 0 THEN 'Carrier'
        WHEN f.weather_delay > 0 THEN 'Weather'
        WHEN f.nas_delay > 0 THEN 'NAS'
        WHEN f.security_delay > 0 THEN 'Security'
        WHEN f.late_aircraft_delay > 0 THEN 'Late Aircraft'
        ELSE 'Unknown'
    END as primary_delay_cause
FROM flights f
JOIN airlines a ON f.airline = a.airline_code
WHERE f.dep_delay > 15;

-- Create view for route performance
CREATE VIEW vw_route_performance AS
SELECT 
    origin || ' → ' || dest as route,
    airline,
    COUNT(*) as total_flights,
    AVG(dep_delay) as avg_delay,
    COUNT(CASE WHEN cancelled = 1 THEN 1 END) as cancelled_count,
    COUNT(CASE WHEN dep_delay <= 15 THEN 1 END) * 100.0 / COUNT(*) as on_time_percentage
FROM flights
GROUP BY origin, dest, airline
HAVING COUNT(*) > 10;

-- Create materialized view for better performance on large datasets
CREATE MATERIALIZED VIEW mv_daily_statistics AS
SELECT 
    flight_date,
    airline,
    COUNT(*) as total_flights,
    COUNT(CASE WHEN cancelled = 1 THEN 1 END) as cancelled_flights,
    COUNT(CASE WHEN dep_delay > 15 THEN 1 END) as delayed_flights,
    AVG(CASE WHEN dep_delay > 0 THEN dep_delay END) as avg_delay,
    SUM(carrier_delay) as total_carrier_delay,
    SUM(weather_delay) as total_weather_delay,
    SUM(nas_delay) as total_nas_delay,
    SUM(security_delay) as total_security_delay,
    SUM(late_aircraft_delay) as total_late_aircraft_delay
FROM flights
GROUP BY flight_date, airline;

CREATE INDEX idx_daily_stats_date ON mv_daily_statistics(flight_date);
CREATE INDEX idx_daily_stats_airline ON mv_daily_statistics(airline);

-- Function to refresh materialized view
CREATE OR REPLACE FUNCTION refresh_daily_statistics()
RETURNS void AS $
BEGIN
    REFRESH MATERIALIZED VIEW mv_daily_statistics;
END;
$ LANGUAGE plpgsql;

-- Advanced query examples for analysis

-- Query 1: Top 10 most delayed routes
CREATE OR REPLACE VIEW vw_most_delayed_routes AS
SELECT 
    origin || ' → ' || dest as route,
    COUNT(*) as flight_count,
    AVG(dep_delay) as avg_delay_minutes,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dep_delay) as median_delay,
    MAX(dep_delay) as max_delay
FROM flights
WHERE dep_delay > 0
GROUP BY origin, dest
HAVING COUNT(*) > 50
ORDER BY avg_delay_minutes DESC
LIMIT 10;

-- Query 2: Weather impact by airport
CREATE OR REPLACE VIEW vw_weather_impact_by_airport AS
SELECT 
    origin as airport,
    COUNT(*) as total_flights,
    SUM(weather_delay) as total_weather_delay_minutes,
    AVG(weather_delay) as avg_weather_delay,
    COUNT(CASE WHEN weather_delay > 0 THEN 1 END) as weather_affected_flights,
    COUNT(CASE WHEN weather_delay > 0 THEN 1 END) * 100.0 / COUNT(*) as weather_impact_percentage
FROM flights
GROUP BY origin
HAVING COUNT(*) > 100
ORDER BY weather_impact_percentage DESC;

-- Query 3: Airline performance comparison
CREATE OR REPLACE VIEW vw_airline_rankings AS
SELECT 
    a.airline_name,
    COUNT(*) as total_flights,
    AVG(f.dep_delay) as avg_delay,
    COUNT(CASE WHEN f.cancelled = 1 THEN 1 END) * 100.0 / COUNT(*) as cancellation_rate,
    COUNT(CASE WHEN f.dep_delay <= 15 THEN 1 END) * 100.0 / COUNT(*) as on_time_rate,
    RANK() OVER (ORDER BY COUNT(CASE WHEN f.dep_delay <= 15 THEN 1 END) * 100.0 / COUNT(*) DESC) as performance_rank
FROM flights f
JOIN airlines a ON f.airline = a.airline_code
GROUP BY a.airline_name
HAVING COUNT(*) > 500
ORDER BY on_time_rate DESC;

-- Query 4: Time-based delay patterns
CREATE OR REPLACE VIEW vw_delay_patterns_by_hour AS
SELECT 
    EXTRACT(HOUR FROM scheduled_dep_time) as departure_hour,
    COUNT(*) as total_flights,
    AVG(dep_delay) as avg_delay,
    COUNT(CASE WHEN dep_delay > 15 THEN 1 END) * 100.0 / COUNT(*) as delay_percentage
FROM flights
WHERE scheduled_dep_time IS NOT NULL
GROUP BY EXTRACT(HOUR FROM scheduled_dep_time)
ORDER BY departure_hour;

-- Query 5: Cascading delay analysis (late aircraft impact)
CREATE OR REPLACE VIEW vw_cascading_delays AS
SELECT 
    airline,
    DATE_TRUNC('month', flight_date) as month,
    SUM(late_aircraft_delay) as total_late_aircraft_delay,
    SUM(late_aircraft_delay) * 100.0 / NULLIF(SUM(dep_delay), 0) as late_aircraft_percentage,
    COUNT(CASE WHEN late_aircraft_delay > 0 THEN 1 END) as flights_affected
FROM flights
WHERE dep_delay > 0
GROUP BY airline, DATE_TRUNC('month', flight_date)
ORDER BY month DESC, total_late_aircraft_delay DESC;
