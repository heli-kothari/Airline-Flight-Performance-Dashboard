package com.flightdashboard;

import javax.swing.*;
import java.awt.*;
import java.sql.*;
import java.util.*;
import java.util.List;

public class FlightDashboardApp extends JFrame {
    private DatabaseManager dbManager;
    private JTabbedPane tabbedPane;
    
    public FlightDashboardApp() {
        setTitle("Airline Flight Performance Dashboard");
        setSize(1200, 800);
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setLocationRelativeTo(null);
        
        dbManager = new DatabaseManager();
        initializeUI();
    }
    
    private void initializeUI() {
        tabbedPane = new JTabbedPane();
        
        // Add different analysis panels
        tabbedPane.addTab("Overview", createOverviewPanel());
        tabbedPane.addTab("Delay Analysis", createDelayAnalysisPanel());
        tabbedPane.addTab("Route Performance", createRoutePanel());
        tabbedPane.addTab("Weather Impact", createWeatherPanel());
        tabbedPane.addTab("Airline Comparison", createAirlinePanel());
        
        add(tabbedPane);
    }
    
    private JPanel createOverviewPanel() {
        JPanel panel = new JPanel(new BorderLayout(10, 10));
        panel.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));
        
        JTextArea statsArea = new JTextArea();
        statsArea.setEditable(false);
        statsArea.setFont(new Font("Monospaced", Font.PLAIN, 14));
        
        JButton refreshButton = new JButton("Refresh Statistics");
        refreshButton.addActionListener(e -> {
            Map<String, Object> stats = dbManager.getOverviewStatistics();
            StringBuilder sb = new StringBuilder();
            sb.append("=== FLIGHT PERFORMANCE OVERVIEW ===\n\n");
            sb.append(String.format("Total Flights: %,d\n", stats.get("totalFlights")));
            sb.append(String.format("Delayed Flights: %,d (%.2f%%)\n", 
                stats.get("delayedFlights"), stats.get("delayPercentage")));
            sb.append(String.format("Cancelled Flights: %,d (%.2f%%)\n", 
                stats.get("cancelledFlights"), stats.get("cancellationPercentage")));
            sb.append(String.format("Average Delay: %.2f minutes\n", stats.get("avgDelay")));
            sb.append(String.format("\nMost Delayed Route: %s\n", stats.get("worstRoute")));
            sb.append(String.format("Best Performing Airline: %s\n", stats.get("bestAirline")));
            statsArea.setText(sb.toString());
        });
        
        JPanel topPanel = new JPanel(new FlowLayout(FlowLayout.LEFT));
        topPanel.add(refreshButton);
        
        panel.add(topPanel, BorderLayout.NORTH);
        panel.add(new JScrollPane(statsArea), BorderLayout.CENTER);
        
        return panel;
    }
    
    private JPanel createDelayAnalysisPanel() {
        JPanel panel = new JPanel(new BorderLayout(10, 10));
        panel.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));
        
        JPanel controlPanel = new JPanel(new FlowLayout(FlowLayout.LEFT));
        JComboBox<String> delayTypeCombo = new JComboBox<>(
            new String[]{"All Delays", "Weather", "Carrier", "NAS", "Security", "Late Aircraft"});
        JButton analyzeButton = new JButton("Analyze Delays");
        
        controlPanel.add(new JLabel("Delay Type:"));
        controlPanel.add(delayTypeCombo);
        controlPanel.add(analyzeButton);
        
        JTextArea resultsArea = new JTextArea();
        resultsArea.setEditable(false);
        resultsArea.setFont(new Font("Monospaced", Font.PLAIN, 12));
        
        analyzeButton.addActionListener(e -> {
            String delayType = (String) delayTypeCombo.getSelectedItem();
            List<DelayInfo> delays = dbManager.getDelayAnalysis(delayType);
            
            StringBuilder sb = new StringBuilder();
            sb.append(String.format("=== %s DELAY ANALYSIS ===\n\n", delayType.toUpperCase()));
            sb.append(String.format("%-15s %-30s %-15s %-15s\n", 
                "Airline", "Route", "Avg Delay", "Count"));
            sb.append("-".repeat(80) + "\n");
            
            for (DelayInfo info : delays) {
                sb.append(String.format("%-15s %-30s %-15.2f %-15d\n",
                    info.airline, info.route, info.avgDelay, info.count));
            }
            
            resultsArea.setText(sb.toString());
        });
        
        panel.add(controlPanel, BorderLayout.NORTH);
        panel.add(new JScrollPane(resultsArea), BorderLayout.CENTER);
        
        return panel;
    }
    
    private JPanel createRoutePanel() {
        JPanel panel = new JPanel(new BorderLayout(10, 10));
        panel.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));
        
        JPanel controlPanel = new JPanel(new FlowLayout(FlowLayout.LEFT));
        JTextField originField = new JTextField(5);
        JTextField destField = new JTextField(5);
        JButton searchButton = new JButton("Search Route");
        
        controlPanel.add(new JLabel("Origin:"));
        controlPanel.add(originField);
        controlPanel.add(new JLabel("Destination:"));
        controlPanel.add(destField);
        controlPanel.add(searchButton);
        
        JTextArea resultsArea = new JTextArea();
        resultsArea.setEditable(false);
        resultsArea.setFont(new Font("Monospaced", Font.PLAIN, 12));
        
        searchButton.addActionListener(e -> {
            String origin = originField.getText().toUpperCase();
            String dest = destField.getText().toUpperCase();
            
            if (origin.isEmpty() || dest.isEmpty()) {
                // Show all routes
                List<RoutePerformance> routes = dbManager.getTopRoutes(20);
                displayRoutePerformance(resultsArea, routes, "TOP 20 ROUTES");
            } else {
                List<RoutePerformance> routes = dbManager.getRoutePerformance(origin, dest);
                displayRoutePerformance(resultsArea, routes, origin + " → " + dest);
            }
        });
        
        panel.add(controlPanel, BorderLayout.NORTH);
        panel.add(new JScrollPane(resultsArea), BorderLayout.CENTER);
        
        return panel;
    }
    
    private void displayRoutePerformance(JTextArea area, List<RoutePerformance> routes, String title) {
        StringBuilder sb = new StringBuilder();
        sb.append(String.format("=== %s ===\n\n", title));
        sb.append(String.format("%-30s %-10s %-15s %-15s %-15s\n",
            "Route", "Flights", "Avg Delay", "Cancel Rate", "On-Time %"));
        sb.append("-".repeat(90) + "\n");
        
        for (RoutePerformance rp : routes) {
            sb.append(String.format("%-30s %-10d %-15.2f %-15.2f%% %-15.2f%%\n",
                rp.route, rp.flightCount, rp.avgDelay, rp.cancellationRate, rp.onTimePercentage));
        }
        
        area.setText(sb.toString());
    }
    
    private JPanel createWeatherPanel() {
        JPanel panel = new JPanel(new BorderLayout(10, 10));
        panel.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));
        
        JButton analyzeButton = new JButton("Analyze Weather Impact");
        JPanel topPanel = new JPanel(new FlowLayout(FlowLayout.LEFT));
        topPanel.add(analyzeButton);
        
        JTextArea resultsArea = new JTextArea();
        resultsArea.setEditable(false);
        resultsArea.setFont(new Font("Monospaced", Font.PLAIN, 12));
        
        analyzeButton.addActionListener(e -> {
            List<WeatherImpact> impacts = dbManager.getWeatherImpact();
            
            StringBuilder sb = new StringBuilder();
            sb.append("=== WEATHER IMPACT ANALYSIS ===\n\n");
            sb.append(String.format("%-20s %-15s %-15s %-15s\n",
                "Condition", "Flights", "Avg Delay", "Cancel Rate"));
            sb.append("-".repeat(70) + "\n");
            
            for (WeatherImpact wi : impacts) {
                sb.append(String.format("%-20s %-15d %-15.2f %-15.2f%%\n",
                    wi.condition, wi.flightCount, wi.avgDelay, wi.cancellationRate));
            }
            
            resultsArea.setText(sb.toString());
        });
        
        panel.add(topPanel, BorderLayout.NORTH);
        panel.add(new JScrollPane(resultsArea), BorderLayout.CENTER);
        
        return panel;
    }
    
    private JPanel createAirlinePanel() {
        JPanel panel = new JPanel(new BorderLayout(10, 10));
        panel.setBorder(BorderFactory.createEmptyBorder(20, 20, 20, 20));
        
        JButton compareButton = new JButton("Compare Airlines");
        JPanel topPanel = new JPanel(new FlowLayout(FlowLayout.LEFT));
        topPanel.add(compareButton);
        
        JTextArea resultsArea = new JTextArea();
        resultsArea.setEditable(false);
        resultsArea.setFont(new Font("Monospaced", Font.PLAIN, 12));
        
        compareButton.addActionListener(e -> {
            List<AirlinePerformance> airlines = dbManager.getAirlineComparison();
            
            StringBuilder sb = new StringBuilder();
            sb.append("=== AIRLINE PERFORMANCE COMPARISON ===\n\n");
            sb.append(String.format("%-20s %-10s %-15s %-15s %-15s\n",
                "Airline", "Flights", "Avg Delay", "Cancel Rate", "On-Time %"));
            sb.append("-".repeat(80) + "\n");
            
            for (AirlinePerformance ap : airlines) {
                sb.append(String.format("%-20s %-10d %-15.2f %-15.2f%% %-15.2f%%\n",
                    ap.airline, ap.flightCount, ap.avgDelay, 
                    ap.cancellationRate, ap.onTimePercentage));
            }
            
            resultsArea.setText(sb.toString());
        });
        
        panel.add(topPanel, BorderLayout.NORTH);
        panel.add(new JScrollPane(resultsArea), BorderLayout.CENTER);
        
        return panel;
    }
    
    public static void main(String[] args) {
        SwingUtilities.invokeLater(() -> {
            FlightDashboardApp app = new FlightDashboardApp();
            app.setVisible(true);
        });
    }
}

// Data classes
class DelayInfo {
    String airline;
    String route;
    double avgDelay;
    int count;
    
    public DelayInfo(String airline, String route, double avgDelay, int count) {
        this.airline = airline;
        this.route = route;
        this.avgDelay = avgDelay;
        this.count = count;
    }
}

class RoutePerformance {
    String route;
    int flightCount;
    double avgDelay;
    double cancellationRate;
    double onTimePercentage;
    
    public RoutePerformance(String route, int flightCount, double avgDelay, 
                           double cancellationRate, double onTimePercentage) {
        this.route = route;
        this.flightCount = flightCount;
        this.avgDelay = avgDelay;
        this.cancellationRate = cancellationRate;
        this.onTimePercentage = onTimePercentage;
    }
}

class WeatherImpact {
    String condition;
    int flightCount;
    double avgDelay;
    double cancellationRate;
    
    public WeatherImpact(String condition, int flightCount, double avgDelay, double cancellationRate) {
        this.condition = condition;
        this.flightCount = flightCount;
        this.avgDelay = avgDelay;
        this.cancellationRate = cancellationRate;
    }
}

class AirlinePerformance {
    String airline;
    int flightCount;
    double avgDelay;
    double cancellationRate;
    double onTimePercentage;
    
    public AirlinePerformance(String airline, int flightCount, double avgDelay,
                             double cancellationRate, double onTimePercentage) {
        this.airline = airline;
        this.flightCount = flightCount;
        this.avgDelay = avgDelay;
        this.cancellationRate = cancellationRate;
        this.onTimePercentage = onTimePercentage;
    }
}
