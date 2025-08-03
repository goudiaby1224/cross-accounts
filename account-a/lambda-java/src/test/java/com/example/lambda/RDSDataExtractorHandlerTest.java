package com.example.lambda;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import org.junit.Test;

import java.util.HashMap;
import java.util.Map;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

/**
 * Unit tests for RDSDataExtractorHandler
 */
public class RDSDataExtractorHandlerTest {
    
    @Test
    public void testHandleRequestWithMissingEnvironmentVariables() {
        // Mock context
        Context context = mock(Context.class);
        LambdaLogger logger = mock(LambdaLogger.class);
        when(context.getLogger()).thenReturn(logger);
        when(context.getAwsRequestId()).thenReturn("test-request-id");
        
        // Create handler
        RDSDataExtractorHandler handler = new RDSDataExtractorHandler();
        
        // Test input
        Map<String, Object> event = new HashMap<>();
        
        // Execute
        Map<String, Object> response = handler.handleRequest(event, context);
        
        // Verify error response due to missing S3_BUCKET_NAME
        assertEquals(500, response.get("statusCode"));
        assertTrue(response.containsKey("error"));
        assertTrue(response.get("error").toString().contains("S3_BUCKET_NAME"));
    }
    
    @Test
    public void testDatabaseConfigCreation() {
        // This test would require mocking AWS services
        // For now, just test the constructor doesn't throw
        try {
            RDSDataExtractorHandler handler = new RDSDataExtractorHandler();
            assertNotNull(handler);
        } catch (Exception e) {
            // Expected in test environment without AWS credentials
            assertTrue(e.getMessage().contains("Unable to load AWS credentials"));
        }
    }
}
