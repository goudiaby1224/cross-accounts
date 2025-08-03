package com.example.lambda.service;

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
import com.amazonaws.services.lambda.runtime.LambdaLogger;

/**
 * Service for handling cross-account AWS operations
 */
public class CrossAccountService {
    
    private final AWSSecurityTokenService stsClient;
    private final String region;
    
    public CrossAccountService(String region) {
        this.region = region;
        this.stsClient = AWSSecurityTokenServiceClientBuilder.standard()
                .withRegion(region)
                .build();
    }
    
    // Constructor for testing
    public CrossAccountService(AWSSecurityTokenService stsClient, String region) {
        this.stsClient = stsClient;
        this.region = region;
    }
    
    /**
     * Assumes cross-account role for RDS access
     */
    public Credentials assumeCrossAccountRole(String accountBId, String roleName, String externalId, 
                                            String requestId, LambdaLogger logger) {
        try {
            String roleArn = String.format("arn:aws:iam::%s:role/%s", 
                    accountBId, 
                    roleName != null ? roleName : "CrossAccountRDSAccessRole");
            
            String sessionName = "LambdaDataExtraction-" + (requestId != null ? requestId : "unknown");
            
            AssumeRoleRequest assumeRoleRequest = new AssumeRoleRequest()
                    .withRoleArn(roleArn)
                    .withRoleSessionName(sessionName)
                    .withDurationSeconds(3600); // 1 hour
            
            if (externalId != null && !externalId.isEmpty() && !"unique-external-id-12345".equals(externalId)) {
                assumeRoleRequest.withExternalId(externalId);
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
    public String getRDSEndpoint(String instanceIdentifier, Credentials credentials, LambdaLogger logger) {
        try {
            AmazonRDS rdsClient;
            
            if (credentials != null) {
                // Use cross-account credentials
                BasicSessionCredentials sessionCredentials = new BasicSessionCredentials(
                        credentials.getAccessKeyId(),
                        credentials.getSecretAccessKey(),
                        credentials.getSessionToken());
                
                rdsClient = AmazonRDSClientBuilder.standard()
                        .withRegion(region)
                        .withCredentials(new AWSStaticCredentialsProvider(sessionCredentials))
                        .build();
            } else {
                // Use default credentials
                rdsClient = AmazonRDSClientBuilder.standard()
                        .withRegion(region)
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
}
