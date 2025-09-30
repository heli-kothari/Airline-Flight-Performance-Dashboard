package com.flightdashboard;

import java.sql.*;
import java.util.*;

public class DatabaseManager {
    private static final String URL = "jdbc:postgresql://localhost:5432/flight_performance";
    private static final String USER = "postgres";
    private static final String PASSWORD = "your_password";
    
    private Connection connection;
    
    public DatabaseManager() {
        try {
            Class.forName("org.postgresql.Driver");
            connection = DriverManager.getConnection(URL, USER, PASSWORD);
            System.out.println("Database connected successfully!");
        } catch (Exception e) {
            System.err.println("Database connection failed: " + e.getMessage());
            e.printStackTrace();
        }
    }
    
    public Map<String, Object> getOverviewStatistics() {
        Map<String, Object> stats = new HashMap<>();
        
        String query = """
            SELECT 
                COUNT(*) as total_flights,
                COUNT(CASE WHEN dep_delay > 15 THEN 1 END) as delayed_flights,
                COUNT(CASE WHEN cancelled = 1 THEN 1 END) as cancelled_flights,
                AVG(CASE WHEN dep_delay > 0 THEN dep_delay END) as avg_delay
            FROM flights
            """;
        
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {
            
            if (rs.next()) {
                long total = rs.getLong("total_flights");
                long delayed = rs.getLong("delayed_flights");
                long cancelled = rs.getLong("cancelled_flights");
                double avgDelay = rs.getDouble("avg_delay");
                
                stats.put("totalFlights", total);
                stats.put("delayedFlights", delayed);
                stats.put("cancelledFlights", cancelled);
                stats.put("avgDelay", avgDelay);
                stats.put("delayPercentage", total > 0 ? (delayed * 100.0 / total) : 0);
                stats.put("cancellationPercentage", total > 0 ? (cancelled * 100.0 / total) : 0);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        
        // Get worst route
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(
                 "SELECT origin || ' → ' || dest as route, AVG(dep_delay) as avg_delay " +
                 "FROM flights WHERE dep_delay > 0 GROUP BY origin, dest " +
                 "ORDER BY avg_delay DESC LIMIT 1")) {
            
            if (rs.next()) {
                stats.put("worstRoute", rs.getString("route"));
            }
        } catch (SQLException e) {
            stats.put("worstRoute", "N/A");
        }
        
        // Get best airline
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(
                 "SELECT airline, " +
                 "COUNT(CASE WHEN dep_delay <= 15 THEN 1 END) * 100.0 / COUNT(*) as on_time_pct " +
                 "FROM flights GROUP BY airline ORDER BY on_time_pct DESC LIMIT 1")) {
            
            if (rs.next()) {
                stats.put("bestAirline", rs.getString("airline"));
            }
        } catch (SQLException e) {
            stats.put("bestAirline", "N/A");
        }
        
        return stats;
    }
    
    public List<DelayInfo> getDelayAnalysis(String delayType) {
        List<DelayInfo> delays = new ArrayList<>();
        
        String delayColumn = switch (delayType) {
            case "Weather" -> "weather_delay";
            case "Carrier" -> "carrier_delay";
            case "NAS" -> "nas_delay";
            case "Security" -> "security_delay";
            case "Late Aircraft" -> "late_aircraft_delay";
            default -> "dep_delay";
        };
        
        String query = String.format("""
            SELECT 
                airline,
                origin || ' → ' || dest as route,
                AVG(%s) as avg_delay,
                COUNT(*) as delay_count
            FROM flights
            WHERE %s > 0
            GROUP BY airline, origin, dest
            ORDER BY avg_delay DESC
            LIMIT 50
            """, delayColumn, delayColumn);
        
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {
            
            while (rs.next()) {
                delays.add(new DelayInfo(
                    rs.getString("airline"),
                    rs.getString("route"),
                    rs.getDouble("avg_delay"),
                    rs.getInt("delay_count")
                ));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        
        return delays;
    }
    
    public List<RoutePerformance> getRoutePerformance(String origin, String dest) {
        List<RoutePerformance> routes = new ArrayList<>();
        
        String query = """
            SELECT 
                origin || ' → ' || dest as route,
                COUNT(*) as flight_count,
                AVG(CASE WHEN dep_delay > 0 THEN dep_delay ELSE 0 END) as avg_delay,
                COUNT(CASE WHEN cancelled = 1 THEN 1 END) * 100.0 / COUNT(*) as cancel_rate,
                COUNT(CASE WHEN dep_delay <= 15 THEN 1 END) * 100.0 / COUNT(*) as on_time_pct
            FROM flights
            WHERE origin = ? AND dest = ?
            GROUP BY origin, dest
            """;
        
        try (PreparedStatement pstmt = connection.prepareStatement(query)) {
            pstmt.setString(1, origin);
            pstmt.setString(2, dest);
            
            ResultSet rs = pstmt.executeQuery();
            
            while (rs.next()) {
                routes.add(new RoutePerformance(
                    rs.getString("route"),
                    rs.getInt("flight_count"),
                    rs.getDouble("avg_delay"),
                    rs.getDouble("cancel_rate"),
                    rs.getDouble("on_time_pct")
                ));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        
        return routes;
    }
    
    public List<RoutePerformance> getTopRoutes(int limit) {
        List<RoutePerformance> routes = new ArrayList<>();
        
        String query = String.format("""
            SELECT 
                origin || ' → ' || dest as route,
                COUNT(*) as flight_count,
                AVG(CASE WHEN dep_delay > 0 THEN dep_delay ELSE 0 END) as avg_delay,
                COUNT(CASE WHEN cancelled = 1 THEN 1 END) * 100.0 / COUNT(*) as cancel_rate,
                COUNT(CASE WHEN dep_delay <= 15 THEN 1 END) * 100.0 / COUNT(*) as on_time_pct
            FROM flights
            GROUP BY origin, dest
            HAVING COUNT(*) > 100
            ORDER BY flight_count DESC
            LIMIT %d
            """, limit);
        
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {
            
            while (rs.next()) {
                routes.add(new RoutePerformance(
                    rs.getString("route"),
                    rs.getInt("flight_count"),
                    rs.getDouble("avg_delay"),
                    rs.getDouble("cancel_rate"),
                    rs.getDouble("on_time_pct")
                ));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        
        return routes;
    }
    
    public List<WeatherImpact> getWeatherImpact() {
        List<WeatherImpact> impacts = new ArrayList<>();
        
        String query = """
            SELECT 
                CASE 
                    WHEN weather_delay > 60 THEN 'Severe Weather'
                    WHEN weather_delay > 30 THEN 'Moderate Weather'
                    WHEN weather_delay > 0 THEN 'Minor Weather'
                    ELSE 'Clear'
                END as condition,
                COUNT(*) as flight_count,
                AVG(dep_delay) as avg_delay,
                COUNT(CASE WHEN cancelled = 1 THEN 1 END) * 100.0 / COUNT(*) as cancel_rate
            FROM flights
            GROUP BY condition
            ORDER BY 
                CASE condition
                    WHEN 'Severe Weather' THEN 1
                    WHEN 'Moderate Weather' THEN 2
                    WHEN 'Minor Weather' THEN 3
                    ELSE 4
                END
            """;
        
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {
            
            while (rs.next()) {
                impacts.add(new WeatherImpact(
                    rs.getString("condition"),
                    rs.getInt("flight_count"),
                    rs.getDouble("avg_delay"),
                    rs.getDouble("cancel_rate")
                ));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        
        return impacts;
    }
    
    public List<AirlinePerformance> getAirlineComparison() {
        List<AirlinePerformance> airlines = new ArrayList<>();
        
        String query = """
            SELECT 
                airline,
                COUNT(*) as flight_count,
                AVG(CASE WHEN dep_delay > 0 THEN dep_delay ELSE 0 END) as avg_delay,
                COUNT(CASE WHEN cancelled = 1 THEN 1 END) * 100.0 / COUNT(*) as cancel_rate,
                COUNT(CASE WHEN dep_delay <= 15 THEN 1 END) * 100.0 / COUNT(*) as on_time_pct
            FROM flights
            GROUP BY airline
            HAVING COUNT(*) > 1000
            ORDER BY on_time_pct DESC
            """;
        
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {
            
            while (rs.next()) {
                airlines.add(new AirlinePerformance(
                    rs.getString("airline"),
                    rs.getInt("flight_count"),
                    rs.getDouble("avg_delay"),
                    rs.getDouble("cancel_rate"),
                    rs.getDouble("on_time_pct")
                ));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        
        return airlines;
    }
    
    public void close() {
        try {
            if (connection != null && !connection.isClosed()) {
                connection.close();
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }
}
