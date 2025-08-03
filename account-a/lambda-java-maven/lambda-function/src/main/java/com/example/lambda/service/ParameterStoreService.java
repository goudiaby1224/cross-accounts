package com.example.lambda.service;

import com.amazonaws.services.simplesystemsmanagement.AWSSimpleSystemsManagement;
import com.amazonaws.services.simplesystemsmanagement.AWSSimpleSystemsManagementClientBuilder;
import com.amazonaws.services.simplesystemsmanagement.model.GetParameterRequest;
import com.amazonaws.services.simplesystemsmanagement.model.GetParameterResult;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.example.lambda.model.DatabaseConfig;

/**
 * Service for interacting with AWS Systems Manager Parameter Store
 */
public class ParameterStoreService {
    
    // Parameter Store parameter names
    private static final String DB_USERNAME_PARAM = "/myapp/db/username";
    private static final String DB_PASSWORD_PARAM = "/myapp/db/password";
    private static final String DB_NAME_PARAM = "/myapp/db/database";
    private static final String DB_INSTANCE_ID_PARAM = "/myapp/db/instance_identifier";
    
    private final AWSSimpleSystemsManagement ssmClient;
    
    public ParameterStoreService(String region) {
        this.ssmClient = AWSSimpleSystemsManagementClientBuilder.standard()
                .withRegion(region)
                .build();
    }
    
    // Constructor for testing
    public ParameterStoreService(AWSSimpleSystemsManagement ssmClient) {
        this.ssmClient = ssmClient;
    }
    
    /**
     * Retrieves database configuration from Parameter Store
     */
    public DatabaseConfig getDatabaseConfig(LambdaLogger logger) {
        try {
            String username = getParameter(DB_USERNAME_PARAM, true, logger);
            String password = getParameter(DB_PASSWORD_PARAM, true, logger);
            String database = getParameter(DB_NAME_PARAM, true, logger);
            String instanceId = getParameter(DB_INSTANCE_ID_PARAM, false, logger);
            
            return new DatabaseConfig(username, password, database, instanceId);
            
        } catch (Exception e) {
            throw new RuntimeException("Failed to retrieve database configuration from Parameter Store", e);
        }
    }
    
    /**
     * Gets a parameter from Parameter Store
     */
    private String getParameter(String parameterName, boolean withDecryption, LambdaLogger logger) {
        try {
            GetParameterRequest request = new GetParameterRequest()
                    .withName(parameterName)
                    .withWithDecryption(withDecryption);
            
            GetParameterResult result = ssmClient.getParameter(request);
            return result.getParameter().getValue();
            
        } catch (Exception e) {
            logger.log("Failed to get parameter: " + parameterName + ", error: " + e.getMessage());
            throw new RuntimeException("Failed to get parameter: " + parameterName, e);
        }
    }
}
