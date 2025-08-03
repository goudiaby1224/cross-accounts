Feature: Cross-Account RDS Data Extraction
  As a data engineer
  I want to extract data from a cross-account RDS database
  So that I can analyze the data in my account

  Background:
    Given the test infrastructure is running
    And the RDS database contains test data
    And the S3 bucket is configured
    And the parameter store contains database configuration

  Scenario: Successful data extraction from cross-account RDS
    Given I have valid cross-account credentials
    And the database connection parameters are configured
    When I trigger the Lambda function for data extraction
    Then the function should complete successfully
    And the data should be extracted from the database
    And the data should be uploaded to S3 as a CSV file
    And the CSV file should contain the expected data structure

  Scenario: Data extraction with custom query
    Given I have valid cross-account credentials
    And the database connection parameters are configured
    And I specify a custom SQL query for users table
    When I trigger the Lambda function for data extraction
    Then the function should complete successfully
    And the extracted data should match the custom query results
    And the CSV file should contain only the queried columns

  Scenario: Handle database connection failure
    Given I have invalid database credentials
    When I trigger the Lambda function for data extraction
    Then the function should fail gracefully
    And an appropriate error message should be returned
    And no data should be uploaded to S3

  Scenario: Handle S3 upload failure
    Given I have valid cross-account credentials
    And the database connection parameters are configured
    But the S3 bucket is not accessible
    When I trigger the Lambda function for data extraction
    Then the function should fail gracefully
    And an appropriate error message should be returned

  Scenario: Extract data with filtering
    Given I have valid cross-account credentials
    And the database connection parameters are configured
    And I specify a query with WHERE clause filtering
    When I trigger the Lambda function for data extraction
    Then the function should complete successfully
    And the CSV file should contain only the filtered records
    And the total record count should match the filter criteria
