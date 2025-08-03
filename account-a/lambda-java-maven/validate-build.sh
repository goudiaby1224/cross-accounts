#!/bin/bash

# Build validation script for Maven project
set -e

echo "🔧 Cross-Account Lambda Maven Project Validation"
echo "================================================"

# Check working directory
if [[ ! -f "pom.xml" ]]; then
    echo "❌ Error: Please run this script from the project root directory"
    exit 1
fi

echo "✅ Project structure validation:"
echo "   - Parent POM: $(ls -la pom.xml | awk '{print $9}')"
echo "   - Lambda module: $(ls -la lambda-function/pom.xml | awk '{print $9}')"
echo "   - Tests module: $(ls -la integration-tests/pom.xml | awk '{print $9}')"

echo ""
echo "🏗️  Building project..."

# Validate project structure
mvn validate -q
echo "✅ Project validation successful"

# Compile without tests
mvn clean compile -q -DskipTests
echo "✅ Compilation successful"

# Package lambda function
mvn package -q -DskipTests
echo "✅ Lambda function packaged"

# Check if JAR was created
if [[ -f "lambda-function/target/lambda-function-1.0.0.jar" ]]; then
    JAR_SIZE=$(ls -lh lambda-function/target/lambda-function-1.0.0.jar | awk '{print $5}')
    echo "✅ Lambda JAR created: $JAR_SIZE"
else
    echo "❌ Lambda JAR not found"
    exit 1
fi

echo ""
echo "📋 Project Summary:"
echo "   - Language: Java 11"
echo "   - Build Tool: Maven 3.x"
echo "   - Lambda Handler: com.example.lambda.RDSDataExtractorHandler"
echo "   - Testing Framework: Cucumber + TestContainers + LocalStack"
echo "   - JAR Location: lambda-function/target/lambda-function-1.0.0.jar"

echo ""
echo "🎯 Next Steps:"
echo "   1. Run integration tests: mvn verify -Pintegration-tests"
echo "   2. Deploy Lambda: aws lambda update-function-code --function-name YourFunction --zip-file fileb://lambda-function/target/lambda-function-1.0.0.jar"
echo "   3. Test deployment: ./run-integration-tests.sh"

echo ""
echo "🎉 Build validation completed successfully!"
