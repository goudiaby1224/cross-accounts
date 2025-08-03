package com.example.lambda.model;

/**
 * Database configuration holder
 */
public class DatabaseConfig {
    private final String username;
    private final String password;
    private final String database;
    private final String instanceIdentifier;
    
    public DatabaseConfig(String username, String password, String database, String instanceIdentifier) {
        this.username = username;
        this.password = password;
        this.database = database;
        this.instanceIdentifier = instanceIdentifier;
    }
    
    public String getUsername() { 
        return username; 
    }
    
    public String getPassword() { 
        return password; 
    }
    
    public String getDatabase() { 
        return database; 
    }
    
    public String getInstanceIdentifier() { 
        return instanceIdentifier; 
    }
    
    @Override
    public String toString() {
        return "DatabaseConfig{" +
                "username='" + username + '\'' +
                ", database='" + database + '\'' +
                ", instanceIdentifier='" + instanceIdentifier + '\'' +
                '}';
    }
}
