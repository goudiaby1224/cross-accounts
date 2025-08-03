package com.example.lambda.integration.config;

import org.testcontainers.containers.LocalStackContainer;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.utility.DockerImageName;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.sts.StsClient;

import java.net.URI;

/**
 * Test infrastructure configuration using TestContainers
 */
public class TestInfrastructure {
    
    private static final DockerImageName LOCALSTACK_IMAGE = 
        DockerImageName.parse("localstack/localstack:2.2.0");
    
    private static final DockerImageName POSTGRES_IMAGE = 
        DockerImageName.parse("postgres:13");
    
    private LocalStackContainer localstack;
    private PostgreSQLContainer<?> postgresql;
    
    public void startInfrastructure() {
        startLocalStack();
        startPostgreSQL();
    }
    
    public void stopInfrastructure() {
        if (postgresql != null && postgresql.isRunning()) {
            postgresql.stop();
        }
        if (localstack != null && localstack.isRunning()) {
            localstack.stop();
        }
    }
    
    private void startLocalStack() {
        localstack = new LocalStackContainer(LOCALSTACK_IMAGE)
            .withServices(
                LocalStackContainer.Service.S3,
                LocalStackContainer.Service.SSM,
                LocalStackContainer.Service.STS
            )
            .withEnv("DEBUG", "1")
            .withEnv("SERVICES", "s3,ssm,sts")
            .withReuse(false);
            
        localstack.start();
    }
    
    private void startPostgreSQL() {
        postgresql = new PostgreSQLContainer<>(POSTGRES_IMAGE)
            .withDatabaseName("testdb")
            .withUsername("testuser")
            .withPassword("testpass")
            .withInitScript("test-data.sql")
            .withReuse(false);
            
        postgresql.start();
    }
    
    public S3Client getS3Client() {
        return S3Client.builder()
            .endpointOverride(localstack.getEndpointOverride(LocalStackContainer.Service.S3))
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create(localstack.getAccessKey(), localstack.getSecretKey())
            ))
            .region(Region.of(localstack.getRegion()))
            .forcePathStyle(true)
            .build();
    }
    
    public SsmClient getSsmClient() {
        return SsmClient.builder()
            .endpointOverride(localstack.getEndpointOverride(LocalStackContainer.Service.SSM))
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create(localstack.getAccessKey(), localstack.getSecretKey())
            ))
            .region(Region.of(localstack.getRegion()))
            .build();
    }
    
    public StsClient getStsClient() {
        return StsClient.builder()
            .endpointOverride(localstack.getEndpointOverride(LocalStackContainer.Service.STS))
            .credentialsProvider(StaticCredentialsProvider.create(
                AwsBasicCredentials.create(localstack.getAccessKey(), localstack.getSecretKey())
            ))
            .region(Region.of(localstack.getRegion()))
            .build();
    }
    
    public String getPostgreSQLJdbcUrl() {
        return postgresql.getJdbcUrl();
    }
    
    public String getPostgreSQLUsername() {
        return postgresql.getUsername();
    }
    
    public String getPostgreSQLPassword() {
        return postgresql.getPassword();
    }
    
    public String getPostgreSQLHost() {
        return postgresql.getHost();
    }
    
    public Integer getPostgreSQLPort() {
        return postgresql.getMappedPort(PostgreSQLContainer.POSTGRESQL_PORT);
    }
    
    public String getLocalStackEndpoint() {
        return localstack.getEndpoint().toString();
    }
}
