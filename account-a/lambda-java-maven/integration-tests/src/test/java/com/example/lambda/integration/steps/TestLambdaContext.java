package com.example.lambda.integration.steps;

import com.amazonaws.services.lambda.runtime.ClientContext;
import com.amazonaws.services.lambda.runtime.CognitoIdentity;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.LambdaLogger;

/**
 * Test implementation of Lambda Context for integration testing
 */
public class TestLambdaContext implements Context {
    
    @Override
    public String getAwsRequestId() {
        return "test-request-id";
    }
    
    @Override
    public String getLogGroupName() {
        return "/aws/lambda/test-function";
    }
    
    @Override
    public String getLogStreamName() {
        return "test-stream";
    }
    
    @Override
    public String getFunctionName() {
        return "test-function";
    }
    
    @Override
    public String getFunctionVersion() {
        return "$LATEST";
    }
    
    @Override
    public String getInvokedFunctionArn() {
        return "arn:aws:lambda:us-east-1:123456789012:function:test-function";
    }
    
    @Override
    public CognitoIdentity getIdentity() {
        return null;
    }
    
    @Override
    public ClientContext getClientContext() {
        return null;
    }
    
    @Override
    public int getRemainingTimeInMillis() {
        return 30000; // 30 seconds
    }
    
    @Override
    public int getMemoryLimitInMB() {
        return 512;
    }
    
    @Override
    public LambdaLogger getLogger() {
        return new LambdaLogger() {
            @Override
            public void log(String message) {
                System.out.println("[LAMBDA] " + message);
            }
            
            @Override
            public void log(byte[] message) {
                System.out.println("[LAMBDA] " + new String(message));
            }
        };
    }
}
