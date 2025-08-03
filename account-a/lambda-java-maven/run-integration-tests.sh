#!/bin/bash

# Integration Test Runner Script
# This script runs the complete integration test suite for the cross-account Lambda function

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

print_color $BLUE "========================================="
print_color $BLUE "Cross-Account Lambda Integration Tests"
print_color $BLUE "========================================="

# Check prerequisites
print_color $YELLOW "Checking prerequisites..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    print_color $RED "Error: Docker is not running. Please start Docker and try again."
    exit 1
fi
print_color $GREEN "✓ Docker is running"

# Check if Maven is available
if ! command -v mvn >/dev/null 2>&1; then
    print_color $RED "Error: Maven is not installed. Please install Maven and try again."
    exit 1
fi
print_color $GREEN "✓ Maven is available"

# Check Java version
JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
if [ "$JAVA_VERSION" -lt 11 ]; then
    print_color $RED "Error: Java 11 or higher is required. Current version: $JAVA_VERSION"
    exit 1
fi
print_color $GREEN "✓ Java $JAVA_VERSION is available"

# Navigate to the Maven project directory
PROJECT_DIR="/Users/noelgoudiaby/cross-account-aws/account-a/lambda-java-maven"
cd "$PROJECT_DIR"

print_color $YELLOW "Project directory: $PROJECT_DIR"

# Clean previous builds
print_color $YELLOW "Cleaning previous builds..."
mvn clean -q

# Compile the project
print_color $YELLOW "Compiling the project..."
if mvn compile -q; then
    print_color $GREEN "✓ Project compiled successfully"
else
    print_color $RED "✗ Project compilation failed"
    exit 1
fi

# Run unit tests first
print_color $YELLOW "Running unit tests..."
if mvn test -q; then
    print_color $GREEN "✓ Unit tests passed"
else
    print_color $RED "✗ Unit tests failed"
    exit 1
fi

# Package the Lambda function
print_color $YELLOW "Packaging Lambda function..."
if mvn package -q -DskipTests; then
    print_color $GREEN "✓ Lambda function packaged successfully"
else
    print_color $RED "✗ Lambda function packaging failed"
    exit 1
fi

# Run integration tests
print_color $YELLOW "Starting integration tests..."
print_color $BLUE "This may take several minutes as containers are downloaded and started..."

if mvn verify -Pintegration-tests -Dlogback.configurationFile=integration-tests/src/test/resources/logback-test.xml; then
    print_color $GREEN "✓ Integration tests completed successfully!"
else
    print_color $RED "✗ Integration tests failed"
    exit 1
fi

# Generate test reports summary
CUCUMBER_REPORTS_DIR="$PROJECT_DIR/integration-tests/target/cucumber-reports"
FAILSAFE_REPORTS_DIR="$PROJECT_DIR/integration-tests/target/failsafe-reports"

print_color $BLUE "========================================="
print_color $BLUE "Test Results Summary"
print_color $BLUE "========================================="

if [ -d "$CUCUMBER_REPORTS_DIR" ]; then
    print_color $GREEN "Cucumber reports available at:"
    print_color $BLUE "  - HTML: $CUCUMBER_REPORTS_DIR/index.html"
    print_color $BLUE "  - JSON: $CUCUMBER_REPORTS_DIR/Cucumber.json"
fi

if [ -d "$FAILSAFE_REPORTS_DIR" ]; then
    print_color $GREEN "Maven Failsafe reports available at:"
    print_color $BLUE "  - $FAILSAFE_REPORTS_DIR/"
fi

# Check for test artifacts
S3_TEST_BUCKET_FILES=$(find "$PROJECT_DIR" -name "*.csv" -type f 2>/dev/null | wc -l || echo 0)
if [ "$S3_TEST_BUCKET_FILES" -gt 0 ]; then
    print_color $GREEN "Test artifacts generated: $S3_TEST_BUCKET_FILES CSV files"
fi

print_color $GREEN "========================================="
print_color $GREEN "All tests completed successfully! 🎉"
print_color $GREEN "========================================="

# Optional: Open test reports in browser (macOS)
if command -v open >/dev/null 2>&1 && [ -f "$CUCUMBER_REPORTS_DIR/index.html" ]; then
    read -p "Open test reports in browser? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "$CUCUMBER_REPORTS_DIR/index.html"
    fi
fi
