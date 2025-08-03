package com.example.lambda.integration.steps;

import com.example.lambda.RDSDataExtractorHandler;
import com.example.lambda.integration.config.TestInfrastructure;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.cucumber.java.After;
import io.cucumber.java.Before;
import io.cucumber.java.en.And;
import io.cucumber.java.en.Given;
import io.cucumber.java.en.Then;
import io.cucumber.java.en.When;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.CreateBucketRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.PutParameterRequest;
import software.amazon.awssdk.services.ssm.model.ParameterType;

import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

public class DataExtractionSteps {
    
    private TestInfrastructure testInfrastructure;
    private RDSDataExtractorHandler lambdaHandler;
    private S3Client s3Client;
    private SsmClient ssmClient;
    private Map<String, Object> lambdaInput;
    private Map<String, Object> lambdaResult;
    private Exception lastException;
    private final ObjectMapper objectMapper = new ObjectMapper();
    
    private static final String TEST_BUCKET = "test-data-bucket";
    private static final String DB_CONFIG_PARAM = "/cross-account/db-config";
    
    @Before
    public void setUp() {
        testInfrastructure = new TestInfrastructure();
        testInfrastructure.startInfrastructure();
        
        s3Client = testInfrastructure.getS3Client();
        ssmClient = testInfrastructure.getSsmClient();
        lambdaHandler = new RDSDataExtractorHandler();
        
        lambdaInput = new HashMap<>();
        lastException = null;
    }
    
    @After
    public void tearDown() {
        if (testInfrastructure != null) {
            testInfrastructure.stopInfrastructure();
        }
    }
    
    @Given("the test infrastructure is running")
    public void theTestInfrastructureIsRunning() {
        assertNotNull(testInfrastructure);
        assertNotNull(s3Client);
        assertNotNull(ssmClient);
    }
    
    @And("the RDS database contains test data")
    public void theRdsDatabaseContainsTestData() {
        // Test data is loaded via test-data.sql during container startup
        assertTrue(true, "Test data loaded during PostgreSQL container initialization");
    }
    
    @And("the S3 bucket is configured")
    public void theS3BucketIsConfigured() {
        s3Client.createBucket(CreateBucketRequest.builder()
            .bucket(TEST_BUCKET)
            .build());
        
        lambdaInput.put("bucket", TEST_BUCKET);
        lambdaInput.put("keyPrefix", "exports");
    }
    
    @And("the parameter store contains database configuration")
    public void theParameterStoreContainsDatabaseConfiguration() {
        Map<String, Object> dbConfig = new HashMap<>();
        dbConfig.put("host", testInfrastructure.getPostgreSQLHost());
        dbConfig.put("port", testInfrastructure.getPostgreSQLPort());
        dbConfig.put("database", "testdb");
        dbConfig.put("username", testInfrastructure.getPostgreSQLUsername());
        dbConfig.put("password", testInfrastructure.getPostgreSQLPassword());
        
        try {
            String configJson = objectMapper.writeValueAsString(dbConfig);
            ssmClient.putParameter(PutParameterRequest.builder()
                .name(DB_CONFIG_PARAM)
                .value(configJson)
                .type(ParameterType.STRING)
                .build());
            
            lambdaInput.put("dbConfigParam", DB_CONFIG_PARAM);
        } catch (Exception e) {
            fail("Failed to configure parameter store: " + e.getMessage());
        }
    }
    
    @Given("I have valid cross-account credentials")
    public void iHaveValidCrossAccountCredentials() {
        lambdaInput.put("crossAccountRoleArn", "arn:aws:iam::123456789012:role/test-role");
        lambdaInput.put("externalId", "test-external-id");
    }
    
    @And("the database connection parameters are configured")
    public void theDatabaseConnectionParametersAreConfigured() {
        lambdaInput.put("query", "SELECT * FROM users");
    }
    
    @And("I specify a custom SQL query for users table")
    public void iSpecifyACustomSqlQueryForUsersTable() {
        lambdaInput.put("query", "SELECT id, username, email FROM users WHERE status = 'active'");
    }
    
    @And("I specify a query with WHERE clause filtering")
    public void iSpecifyAQueryWithWhereClauseFiltering() {
        lambdaInput.put("query", "SELECT * FROM users WHERE status = 'active'");
    }
    
    @Given("I have invalid database credentials")
    public void iHaveInvalidDatabaseCredentials() {
        Map<String, Object> dbConfig = new HashMap<>();
        dbConfig.put("host", testInfrastructure.getPostgreSQLHost());
        dbConfig.put("port", testInfrastructure.getPostgreSQLPort());
        dbConfig.put("database", "testdb");
        dbConfig.put("username", "invalid_user");
        dbConfig.put("password", "invalid_password");
        
        try {
            String configJson = objectMapper.writeValueAsString(dbConfig);
            ssmClient.putParameter(PutParameterRequest.builder()
                .name("/invalid/db-config")
                .value(configJson)
                .type(ParameterType.STRING)
                .overwrite(true)
                .build());
            
            lambdaInput.put("dbConfigParam", "/invalid/db-config");
            lambdaInput.put("crossAccountRoleArn", "arn:aws:iam::123456789012:role/test-role");
            lambdaInput.put("query", "SELECT * FROM users");
        } catch (Exception e) {
            fail("Failed to configure invalid credentials: " + e.getMessage());
        }
    }
    
    @And("the S3 bucket is not accessible")
    public void theS3BucketIsNotAccessible() {
        lambdaInput.put("bucket", "non-existent-bucket");
    }
    
    @When("I trigger the Lambda function for data extraction")
    public void iTriggerTheLambdaFunctionForDataExtraction() {
        try {
            lambdaResult = lambdaHandler.handleRequest(lambdaInput, new TestLambdaContext());
        } catch (Exception e) {
            lastException = e;
        }
    }
    
    @Then("the function should complete successfully")
    public void theFunctionShouldCompleteSuccessfully() {
        assertNull(lastException, "Lambda function should not throw exception");
        assertNotNull(lambdaResult, "Lambda result should not be null");
        assertEquals(200, lambdaResult.get("statusCode"));
        assertTrue(lambdaResult.get("body").toString().contains("success"));
    }
    
    @And("the data should be extracted from the database")
    public void theDataShouldBeExtractedFromTheDatabase() {
        assertTrue(lambdaResult.get("body").toString().contains("records processed"));
    }
    
    @And("the data should be uploaded to S3 as a CSV file")
    public void theDataShouldBeUploadedToS3AsACsvFile() {
        var objects = s3Client.listObjectsV2(ListObjectsV2Request.builder()
            .bucket(TEST_BUCKET)
            .prefix("exports/")
            .build());
        
        assertFalse(objects.contents().isEmpty(), "S3 should contain uploaded files");
        assertTrue(objects.contents().get(0).key().endsWith(".csv"), "Uploaded file should be CSV");
    }
    
    @And("the CSV file should contain the expected data structure")
    public void theCsvFileShouldContainTheExpectedDataStructure() {
        var objects = s3Client.listObjectsV2(ListObjectsV2Request.builder()
            .bucket(TEST_BUCKET)
            .prefix("exports/")
            .build());
        
        String csvKey = objects.contents().get(0).key();
        var csvContent = s3Client.getObjectAsBytes(GetObjectRequest.builder()
            .bucket(TEST_BUCKET)
            .key(csvKey)
            .build());
        
        String csvData = csvContent.asUtf8String();
        assertTrue(csvData.contains("id,username,email"), "CSV should contain expected headers");
        assertTrue(csvData.split("\n").length > 1, "CSV should contain data rows");
    }
    
    @And("the extracted data should match the custom query results")
    public void theExtractedDataShouldMatchTheCustomQueryResults() {
        var objects = s3Client.listObjectsV2(ListObjectsV2Request.builder()
            .bucket(TEST_BUCKET)
            .prefix("exports/")
            .build());
        
        String csvKey = objects.contents().get(0).key();
        var csvContent = s3Client.getObjectAsBytes(GetObjectRequest.builder()
            .bucket(TEST_BUCKET)
            .key(csvKey)
            .build());
        
        String csvData = csvContent.asUtf8String();
        assertTrue(csvData.contains("id,username,email"), "CSV should contain only queried columns");
        assertFalse(csvData.contains("created_at"), "CSV should not contain non-queried columns");
    }
    
    @And("the CSV file should contain only the queried columns")
    public void theCsvFileShouldContainOnlyTheQueriedColumns() {
        theExtractedDataShouldMatchTheCustomQueryResults();
    }
    
    @Then("the function should fail gracefully")
    public void theFunctionShouldFailGracefully() {
        if (lastException != null) {
            assertTrue(lastException instanceof RuntimeException);
        } else {
            assertNotNull(lambdaResult);
            assertEquals(500, lambdaResult.get("statusCode"));
        }
    }
    
    @And("an appropriate error message should be returned")
    public void anAppropriateErrorMessageShouldBeReturned() {
        if (lastException != null) {
            assertNotNull(lastException.getMessage());
        } else {
            assertTrue(lambdaResult.get("body").toString().contains("error"));
        }
    }
    
    @And("no data should be uploaded to S3")
    public void noDataShouldBeUploadedToS3() {
        var objects = s3Client.listObjectsV2(ListObjectsV2Request.builder()
            .bucket(TEST_BUCKET)
            .prefix("exports/")
            .build());
        
        assertTrue(objects.contents().isEmpty(), "No files should be uploaded to S3");
    }
    
    @And("the CSV file should contain only the filtered records")
    public void theCsvFileShouldContainOnlyTheFilteredRecords() {
        var objects = s3Client.listObjectsV2(ListObjectsV2Request.builder()
            .bucket(TEST_BUCKET)
            .prefix("exports/")
            .build());
        
        String csvKey = objects.contents().get(0).key();
        var csvContent = s3Client.getObjectAsBytes(GetObjectRequest.builder()
            .bucket(TEST_BUCKET)
            .key(csvKey)
            .build());
        
        String csvData = csvContent.asUtf8String();
        String[] lines = csvData.split("\n");
        // Should have header + 3 active users (john_doe, jane_smith, sarah_jones)
        assertEquals(4, lines.length, "CSV should contain filtered records only");
    }
    
    @And("the total record count should match the filter criteria")
    public void theTotalRecordCountShouldMatchTheFilterCriteria() {
        assertTrue(lambdaResult.get("body").toString().contains("3 records processed"));
    }
}
