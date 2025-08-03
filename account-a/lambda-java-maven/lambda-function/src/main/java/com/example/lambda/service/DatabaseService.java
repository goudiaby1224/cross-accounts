package com.example.lambda.service;

import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.example.lambda.model.DatabaseConfig;

import java.sql.*;
import java.util.*;

/**
 * Service for database operations
 */
public class DatabaseService {
    
    /**
     * Extracts data from the database
     */
    public List<Map<String, Object>> extractData(String endpoint, DatabaseConfig dbConfig, 
                                                String query, LambdaLogger logger) {
        List<Map<String, Object>> data = new ArrayList<>();
        
        // Database connection properties
        Properties props = new Properties();
        props.setProperty("user", dbConfig.getUsername());
        props.setProperty("password", dbConfig.getPassword());
        props.setProperty("ssl", "true");
        props.setProperty("sslmode", "require");
        props.setProperty("connectTimeout", "30");
        props.setProperty("socketTimeout", "30");
        
        String jdbcUrl = String.format("jdbc:postgresql://%s:5432/%s", endpoint, dbConfig.getDatabase());
        
        try (Connection connection = DriverManager.getConnection(jdbcUrl, props)) {
            logger.log("Connected to database successfully");
            
            try (PreparedStatement statement = connection.prepareStatement(query);
                 ResultSet resultSet = statement.executeQuery()) {
                
                ResultSetMetaData metaData = resultSet.getMetaData();
                int columnCount = metaData.getColumnCount();
                
                while (resultSet.next()) {
                    Map<String, Object> row = new LinkedHashMap<>();
                    
                    for (int i = 1; i <= columnCount; i++) {
                        String columnName = metaData.getColumnLabel(i);
                        Object value = resultSet.getObject(i);
                        row.put(columnName, value);
                    }
                    
                    data.add(row);
                }
            }
            
        } catch (SQLException e) {
            logger.log("Database error: " + e.getMessage());
            throw new RuntimeException("Failed to extract data from database", e);
        }
        
        return data;
    }
}
