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
    
    // Parameter Store parameter names
    private static final String DB_USERNAME_PARAM = "/myapp/db/username";
    private static final String DB_PASSWORD_PARAM = "/myapp/db/password";
    private static final String DB_NAME_PARAM = "/myapp/db/database";
    private static final String DB_INSTANCE_ID_PARAM = "/myapp/db/instance_identifier";
    
    private final AmazonS3 s3Client;
    private final AWSSimpleSystemsManagement ssmClient;
    private final AWSSecurityTokenService stsClient;
    
    public RDSDataExtractorHandler() {
        this.s3Client = AmazonS3ClientBuilder.standard()
                .withRegion(AWS_REGION != null ? AWS_REGION : "us-east-1")
                .build();
        this.ssmClient = AWSSimpleSystemsManagementClientBuilder.standard()
                .withRegion(AWS_REGION != null ? AWS_REGION : "us-east-1")
                .build();
        this.stsClient = AWSSecurityTokenServiceClientBuilder.standard()
                .withRegion(AWS_REGION != null ? AWS_REGION : "us-east-1")
                .build();
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
            DatabaseConfig dbConfig = getDatabaseConfig(logger);
            logger.log("Database configuration retrieved from Parameter Store");
            
            // Assume cross-account role if needed
            Credentials crossAccountCredentials = null;
            if (ACCOUNT_B_ID != null && !ACCOUNT_B_ID.isEmpty()) {
                crossAccountCredentials = assumeCrossAccountRole(context.getAwsRequestId(), logger);
                logger.log("Successfully assumed cross-account role");
            }
            
            // Get RDS endpoint
            String dbEndpoint = getRDSEndpoint(dbConfig.getInstanceIdentifier(), crossAccountCredentials, logger);
            logger.log("Retrieved RDS endpoint: " + dbEndpoint);
            
            // Extract data from database
            List<Map<String, Object>> extractedData = extractDataFromDatabase(dbEndpoint, dbConfig, logger);
            logger.log("Extracted " + extractedData.size() + " records from database");
            
            // Convert data to CSV and upload to S3
            String s3Key = uploadDataToS3(extractedData, logger);
            logger.log("Data uploaded to S3 successfully: " + s3Key);
            
            // Prepare success response
            response.put("statusCode", 200);
            response.put("message", "Data extraction completed successfully");
            response.put("recordsProcessed", extractedData.size());
            response.put("s3Location", "s3://" + S3_BUCKET_NAME + "/" + s3Key);
            response.put("timestamp", LocalDateTime.now().toString());
            response.put("requestId", context.getAwsRequestId());
            
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
    
    /**
     * Retrieves database configuration from Parameter Store
     */
    private DatabaseConfig getDatabaseConfig(LambdaLogger logger) {
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
    
    /**
     * Assumes cross-account role for RDS access
     */
    private Credentials assumeCrossAccountRole(String requestId, LambdaLogger logger) {
        try {
            String roleArn = String.format("arn:aws:iam::%s:role/%s", 
                    ACCOUNT_B_ID, 
                    CROSS_ACCOUNT_ROLE_NAME != null ? CROSS_ACCOUNT_ROLE_NAME : "CrossAccountRDSAccessRole");
            
            String sessionName = "LambdaDataExtraction-" + requestId;
            
            AssumeRoleRequest assumeRoleRequest = new AssumeRoleRequest()
                    .withRoleArn(roleArn)
                    .withRoleSessionName(sessionName)
                    .withDurationSeconds(3600); // 1 hour
            
            if (EXTERNAL_ID != null && !EXTERNAL_ID.isEmpty()) {
                assumeRoleRequest.withExternalId(EXTERNAL_ID);
            }
            
            AssumeRoleResult assumeRoleResult = stsClient.assumeRole(assumeRoleRequest);
            return assumeRoleResult.getCredentials();
            
        } catch (Exception e) {
            logger.log("Failed to assume cross-account role: " + e.getMessage());
            throw new RuntimeException("Failed to assume cross-account role", e);
        }
    }
    
    /**
     * Gets RDS endpoint using describe-db-instances
     */
    private String getRDSEndpoint(String instanceIdentifier, Credentials credentials, LambdaLogger logger) {
        try {
            AmazonRDS rdsClient;
            
            if (credentials != null) {
                // Use cross-account credentials
                BasicSessionCredentials sessionCredentials = new BasicSessionCredentials(
                        credentials.getAccessKeyId(),
                        credentials.getSecretAccessKey(),
                        credentials.getSessionToken());
                
                rdsClient = AmazonRDSClientBuilder.standard()
                        .withRegion(AWS_REGION != null ? AWS_REGION : "us-east-1")
                        .withCredentials(new AWSStaticCredentialsProvider(sessionCredentials))
                        .build();
            } else {
                // Use default credentials
                rdsClient = AmazonRDSClientBuilder.standard()
                        .withRegion(AWS_REGION != null ? AWS_REGION : "us-east-1")
                        .build();
            }
            
            DescribeDBInstancesRequest request = new DescribeDBInstancesRequest()
                    .withDBInstanceIdentifier(instanceIdentifier);
            
            DescribeDBInstancesResult result = rdsClient.describeDBInstances(request);
            
            if (result.getDBInstances().isEmpty()) {
                throw new RuntimeException("No RDS instance found with identifier: " + instanceIdentifier);
            }
            
            DBInstance dbInstance = result.getDBInstances().get(0);
            
            if (!"available".equals(dbInstance.getDBInstanceStatus())) {
                throw new RuntimeException("RDS instance is not available. Status: " + dbInstance.getDBInstanceStatus());
            }
            
            return dbInstance.getEndpoint().getAddress();
            
        } catch (Exception e) {
            logger.log("Failed to get RDS endpoint: " + e.getMessage());
            throw new RuntimeException("Failed to get RDS endpoint", e);
        }
    }
    
    /**
     * Extracts data from the database
     */
    private List<Map<String, Object>> extractDataFromDatabase(String endpoint, DatabaseConfig dbConfig, LambdaLogger logger) {
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
            
            String query = DB_QUERY != null && !DB_QUERY.isEmpty() 
                    ? DB_QUERY 
                    : "SELECT * FROM information_schema.tables WHERE table_schema = 'public' LIMIT 100";
            
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
    
    /**
     * Uploads extracted data to S3 as CSV
     */
    private String uploadDataToS3(List<Map<String, Object>> data, LambdaLogger logger) {
        try {
            // Generate S3 key
            String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd_HH-mm-ss"));
            String randomSuffix = String.valueOf(ThreadLocalRandom.current().nextInt(1000, 9999));
            String filename = String.format("%s_%s_%s.csv", 
                    CSV_FILENAME_PREFIX != null ? CSV_FILENAME_PREFIX : "data_extract",
                    timestamp, 
                    randomSuffix);
            
            String s3Key = S3_KEY_PREFIX != null && !S3_KEY_PREFIX.isEmpty() 
                    ? S3_KEY_PREFIX + "/" + filename 
                    : filename;
            
            // Create CSV content
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            OutputStreamWriter osw = new OutputStreamWriter(baos);
            CSVWriter csvWriter = new CSVWriter(osw);
            
            if (!data.isEmpty()) {
                // Write header
                Map<String, Object> firstRow = data.get(0);
                String[] headers = firstRow.keySet().toArray(new String[0]);
                csvWriter.writeNext(headers);
                
                // Write data rows
                for (Map<String, Object> row : data) {
                    String[] values = new String[headers.length];
                    for (int i = 0; i < headers.length; i++) {
                        Object value = row.get(headers[i]);
                        values[i] = value != null ? value.toString() : "";
                    }
                    csvWriter.writeNext(values);
                }
            }
            
            csvWriter.close();
            
            // Upload to S3
            byte[] csvBytes = baos.toByteArray();
            ByteArrayInputStream bais = new ByteArrayInputStream(csvBytes);
            
            ObjectMetadata metadata = new ObjectMetadata();
            metadata.setContentLength(csvBytes.length);
            metadata.setContentType("text/csv");
            metadata.addUserMetadata("extraction-timestamp", LocalDateTime.now().toString());
            metadata.addUserMetadata("record-count", String.valueOf(data.size()));
            
            PutObjectRequest putRequest = new PutObjectRequest(S3_BUCKET_NAME, s3Key, bais, metadata);
            s3Client.putObject(putRequest);
            
            logger.log("CSV file uploaded to S3: " + s3Key + " (Size: " + csvBytes.length + " bytes)");
            
            return s3Key;
            
        } catch (Exception e) {
            logger.log("Failed to upload data to S3: " + e.getMessage());
            throw new RuntimeException("Failed to upload data to S3", e);
        }
    }
    
    /**
     * Database configuration holder
     */
    private static class DatabaseConfig {
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
        
        public String getUsername() { return username; }
        public String getPassword() { return password; }
        public String getDatabase() { return database; }
        public String getInstanceIdentifier() { return instanceIdentifier; }
    }
}
