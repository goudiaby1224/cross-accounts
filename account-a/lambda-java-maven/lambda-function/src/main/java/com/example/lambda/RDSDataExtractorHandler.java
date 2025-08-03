package com.example.lambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;
import com.amazonaws.services.s3.model.ObjectMetadata;
import com.amazonaws.services.s3.model.PutObjectRequest;
import com.amazonaws.services.simplesystemsmanagement.AWSSimpleSystemsManagement;
import com.amazonaws.services.simplesystemsmanagement.AWSSimpleSystemsManagementClientBuilder;
import com.amazonaws.services.simplesystemsmanagement.model.GetParameterRequest;
import com.amazonaws.services.simplesystemsmanagement.model.GetParameterResult;
import com.amazonaws.services.securitytoken.AWSSecurityTokenService;
import com.amazonaws.services.securitytoken.AWSSecurityTokenServiceClientBuilder;
import com.amazonaws.services.securitytoken.model.AssumeRoleRequest;
import com.amazonaws.services.securitytoken.model.AssumeRoleResult;
import com.amazonaws.services.securitytoken.model.Credentials;
import com.amazonaws.auth.BasicSessionCredentials;
import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.services.rds.AmazonRDS;
import com.amazonaws.services.rds.AmazonRDSClientBuilder;
import com.amazonaws.services.rds.model.DescribeDBInstancesRequest;
import com.amazonaws.services.rds.model.DescribeDBInstancesResult;
import com.amazonaws.services.rds.model.DBInstance;

import com.opencsv.CSVWriter;
import com.example.lambda.model.DatabaseConfig;
import com.example.lambda.service.DatabaseService;
import com.example.lambda.service.S3Service;
import com.example.lambda.service.ParameterStoreService;
import com.example.lambda.service.CrossAccountService;

import java.io.*;
import java.sql.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.ThreadLocalRandom;

/**
 * AWS Lambda function that extracts data from cross-account RDS database
 * and stores it as CSV in S3 bucket
 */
public class RDSDataExtractorHandler implements RequestHandler<Map<String, Object>, Map<String, Object>> {
    
    private static final String ACCOUNT_B_ID = System.getenv("ACCOUNT_B_ID");
    private static final String AWS_REGION = System.getenv("AWS_REGION");
    private static final String CROSS_ACCOUNT_ROLE_NAME = System.getenv("CROSS_ACCOUNT_ROLE_NAME");
    private static final String EXTERNAL_ID = System.getenv("EXTERNAL_ID");
    private static final String S3_BUCKET_NAME = System.getenv("S3_BUCKET_NAME");
    private static final String S3_KEY_PREFIX = System.getenv("S3_KEY_PREFIX");
    private static final String DB_QUERY = System.getenv("DB_QUERY");
    private static final String CSV_FILENAME_PREFIX = System.getenv("CSV_FILENAME_PREFIX");
    
    private final ParameterStoreService parameterStoreService;
    private final CrossAccountService crossAccountService;
    private final DatabaseService databaseService;
    private final S3Service s3Service;
    
    public RDSDataExtractorHandler() {
        String region = AWS_REGION != null ? AWS_REGION : "us-east-1";
        this.parameterStoreService = new ParameterStoreService(region);
        this.crossAccountService = new CrossAccountService(region);
        this.databaseService = new DatabaseService();
        this.s3Service = new S3Service(region);
    }
    
    // Constructor for testing
    public RDSDataExtractorHandler(ParameterStoreService parameterStoreService,
                                   CrossAccountService crossAccountService,
                                   DatabaseService databaseService,
                                   S3Service s3Service) {
        this.parameterStoreService = parameterStoreService;
        this.crossAccountService = crossAccountService;
        this.databaseService = databaseService;
        this.s3Service = s3Service;
    }
    
    @Override
    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {
        LambdaLogger logger = context.getLogger();
        Map<String, Object> response = new HashMap<>();
        
        try {
            logger.log("Starting RDS data extraction process...");
            
            // Validate environment variables
            validateEnvironmentVariables();
            logger.log("Environment variables validated successfully");
            
            // Get database configuration from Parameter Store
            DatabaseConfig dbConfig = parameterStoreService.getDatabaseConfig(logger);
            logger.log("Database configuration retrieved from Parameter Store");
            
            // Assume cross-account role if needed
            Credentials crossAccountCredentials = null;
            if (ACCOUNT_B_ID != null && !ACCOUNT_B_ID.isEmpty()) {
                crossAccountCredentials = crossAccountService.assumeCrossAccountRole(
                    ACCOUNT_B_ID, 
                    CROSS_ACCOUNT_ROLE_NAME, 
                    EXTERNAL_ID,
                    context.getAwsRequestId(), 
                    logger
                );
                logger.log("Successfully assumed cross-account role");
            }
            
            // Get RDS endpoint
            String dbEndpoint = crossAccountService.getRDSEndpoint(
                dbConfig.getInstanceIdentifier(), 
                crossAccountCredentials, 
                logger
            );
            logger.log("Retrieved RDS endpoint: " + dbEndpoint);
            
            // Extract data from database
            String query = DB_QUERY != null && !DB_QUERY.isEmpty() 
                    ? DB_QUERY 
                    : "SELECT table_name, table_schema, table_type FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name LIMIT 100";
            
            List<Map<String, Object>> extractedData = databaseService.extractData(dbEndpoint, dbConfig, query, logger);
            logger.log("Extracted " + extractedData.size() + " records from database");
            
            // Convert data to CSV and upload to S3
            String s3Key = s3Service.uploadDataToS3(
                extractedData, 
                S3_BUCKET_NAME, 
                S3_KEY_PREFIX, 
                CSV_FILENAME_PREFIX,
                logger
            );
            logger.log("Data uploaded to S3 successfully: " + s3Key);
            
            // Prepare success response
            response.put("statusCode", 200);
            response.put("message", "Data extraction completed successfully");
            response.put("recordsProcessed", extractedData.size());
            response.put("s3Location", "s3://" + S3_BUCKET_NAME + "/" + s3Key);
            response.put("timestamp", LocalDateTime.now().toString());
            response.put("requestId", context.getAwsRequestId());
            response.put("query", query);
            
        } catch (Exception e) {
            logger.log("Error in data extraction: " + e.getMessage());
            e.printStackTrace();
            
            response.put("statusCode", 500);
            response.put("error", e.getMessage());
            response.put("errorType", e.getClass().getSimpleName());
            response.put("requestId", context.getAwsRequestId());
        }
        
        return response;
    }
    
    /**
     * Validates required environment variables
     */
    private void validateEnvironmentVariables() {
        List<String> missingVars = new ArrayList<>();
        
        if (S3_BUCKET_NAME == null || S3_BUCKET_NAME.isEmpty()) {
            missingVars.add("S3_BUCKET_NAME");
        }
        
        if (!missingVars.isEmpty()) {
            throw new IllegalArgumentException("Missing required environment variables: " + String.join(", ", missingVars));
        }
    }
}
