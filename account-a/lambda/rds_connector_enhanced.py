import os
import json
import boto3
import psycopg2
import logging
from typing import Dict, Any, Optional
from botocore.exceptions import ClientError, NoCredentialsError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Constants
EXTERNAL_ID = os.environ.get('EXTERNAL_ID', 'unique-external-id-12345')
ACCOUNT_B_ID = os.environ.get('ACCOUNT_B_ID')
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
CROSS_ACCOUNT_ROLE_NAME = os.environ.get('CROSS_ACCOUNT_ROLE_NAME', 'CrossAccountRDSAccessRole')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for cross-account RDS connection.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dictionary containing status code and response body
    """
    try:
        logger.info("Starting cross-account RDS connection process")
        
        # Validate environment variables
        if not ACCOUNT_B_ID:
            raise ValueError("ACCOUNT_B_ID environment variable is required")
        
        # Initialize clients
        ssm_client = boto3.client('ssm', region_name=AWS_REGION)
        sts_client = boto3.client('sts', region_name=AWS_REGION)
        
        # Get parameters from Parameter Store
        db_params = get_parameters_from_ssm(ssm_client)
        logger.info("Successfully retrieved database parameters from Parameter Store")
        
        # Assume role in Account B
        assumed_role = assume_cross_account_role(sts_client, context.aws_request_id)
        logger.info("Successfully assumed cross-account role")
        
        # Create RDS client with assumed role credentials
        rds_client = create_rds_client(assumed_role)
        
        # Get RDS endpoint
        db_endpoint = get_rds_endpoint(rds_client, db_params['db_instance_identifier'])
        logger.info(f"Retrieved RDS endpoint: {db_endpoint}")
        
        # Connect to database and execute test query
        connection = connect_to_database(db_endpoint, db_params)
        result = execute_query(connection, "SELECT version(), current_database(), current_user;")
        
        logger.info("Successfully connected to RDS and executed query")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'message': 'Successfully connected to cross-account RDS',
                'database_info': {
                    'endpoint': db_endpoint,
                    'database': db_params['db_database'],
                    'user': db_params['db_username']
                },
                'query_result': result,
                'timestamp': context.aws_request_id
            }, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__,
                'request_id': context.aws_request_id
            })
        }

def get_parameters_from_ssm(ssm_client: boto3.client) -> Dict[str, str]:
    """
    Retrieve database parameters from Parameter Store.
    
    Args:
        ssm_client: Boto3 SSM client
        
    Returns:
        Dictionary containing database parameters
        
    Raises:
        ClientError: If parameters cannot be retrieved
    """
    try:
        param_names = [
            '/myapp/db/username',
            '/myapp/db/password',
            '/myapp/db/database',
            '/myapp/db/instance_identifier'
        ]
        
        logger.info("Retrieving parameters from Parameter Store")
        response = ssm_client.get_parameters(
            Names=param_names,
            WithDecryption=True
        )
        
        # Check if all parameters were retrieved
        if len(response['Parameters']) != len(param_names):
            missing_params = set(param_names) - {param['Name'] for param in response['Parameters']}
            raise ValueError(f"Missing required parameters: {missing_params}")
        
        # Process parameters
        parameters = {}
        for param in response['Parameters']:
            key = param['Name'].split('/')[-1]  # Get last part of parameter name
            parameters[f'db_{key}'] = param['Value']
        
        # Validate required parameters
        required_keys = ['db_username', 'db_password', 'db_database', 'db_instance_identifier']
        missing_keys = [key for key in required_keys if key not in parameters]
        if missing_keys:
            raise ValueError(f"Missing required parameter keys: {missing_keys}")
        
        return parameters
        
    except ClientError as e:
        logger.error(f"Failed to retrieve parameters from SSM: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error retrieving parameters: {e}")
        raise

def assume_cross_account_role(sts_client: boto3.client, request_id: str = None) -> Dict[str, str]:
    """
    Assume role in Account B for cross-account access.
    
    Args:
        sts_client: Boto3 STS client
        request_id: AWS request ID for session naming
        
    Returns:
        Dictionary containing temporary credentials
        
    Raises:
        ClientError: If role assumption fails
    """
    try:
        role_arn = f'arn:aws:iam::{ACCOUNT_B_ID}:role/{CROSS_ACCOUNT_ROLE_NAME}'
        session_name = f'LambdaRDSAccess-{request_id}' if request_id else 'LambdaRDSAccess'
        
        assume_role_params = {
            'RoleArn': role_arn,
            'RoleSessionName': session_name,
            'DurationSeconds': 3600  # 1 hour
        }
        
        # Add external ID if configured
        if EXTERNAL_ID and EXTERNAL_ID != 'unique-external-id-12345':
            assume_role_params['ExternalId'] = EXTERNAL_ID
        
        logger.info(f"Assuming role: {role_arn}")
        response = sts_client.assume_role(**assume_role_params)
        
        return response['Credentials']
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'AccessDenied':
            logger.error("Access denied when assuming role. Check trust relationship and permissions.")
        elif error_code == 'InvalidParameterValue':
            logger.error("Invalid parameter value. Check external ID and role ARN.")
        else:
            logger.error(f"Failed to assume role: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error assuming role: {e}")
        raise

def create_rds_client(credentials: Dict[str, str]) -> boto3.client:
    """
    Create RDS client with assumed role credentials.
    
    Args:
        credentials: Temporary credentials from STS
        
    Returns:
        Boto3 RDS client
    """
    return boto3.client(
        'rds',
        region_name=AWS_REGION,
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken']
    )

def get_rds_endpoint(rds_client: boto3.client, db_instance_identifier: str) -> str:
    """
    Get RDS instance endpoint.
    
    Args:
        rds_client: Boto3 RDS client
        db_instance_identifier: RDS instance identifier
        
    Returns:
        RDS endpoint address
        
    Raises:
        ClientError: If RDS instance cannot be found or accessed
    """
    try:
        logger.info(f"Retrieving endpoint for RDS instance: {db_instance_identifier}")
        response = rds_client.describe_db_instances(
            DBInstanceIdentifier=db_instance_identifier
        )
        
        db_instances = response['DBInstances']
        if not db_instances:
            raise ValueError(f"No RDS instance found with identifier: {db_instance_identifier}")
        
        db_instance = db_instances[0]
        
        # Check if instance is available
        if db_instance['DBInstanceStatus'] != 'available':
            raise ValueError(f"RDS instance is not available. Status: {db_instance['DBInstanceStatus']}")
        
        endpoint = db_instance['Endpoint']['Address']
        port = db_instance['Endpoint']['Port']
        
        logger.info(f"RDS endpoint: {endpoint}:{port}")
        return endpoint
        
    except ClientError as e:
        logger.error(f"Failed to get RDS endpoint: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error getting RDS endpoint: {e}")
        raise

def connect_to_database(endpoint: str, db_params: Dict[str, str]) -> psycopg2.connection:
    """
    Connect to PostgreSQL database.
    
    Args:
        endpoint: RDS endpoint
        db_params: Database connection parameters
        
    Returns:
        Database connection object
        
    Raises:
        psycopg2.Error: If database connection fails
    """
    try:
        logger.info(f"Connecting to database at {endpoint}")
        connection = psycopg2.connect(
            host=endpoint,
            port=5432,
            database=db_params['db_database'],
            user=db_params['db_username'],
            password=db_params['db_password'],
            connect_timeout=30,
            sslmode='require'  # Force SSL connection
        )
        
        # Test the connection
        connection.autocommit = True
        logger.info("Successfully connected to database")
        return connection
        
    except psycopg2.Error as e:
        logger.error(f"Database connection failed: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error connecting to database: {e}")
        raise

def execute_query(connection: psycopg2.connection, query: str) -> list:
    """
    Execute a query and return results.
    
    Args:
        connection: Database connection
        query: SQL query to execute
        
    Returns:
        List of query results
        
    Raises:
        psycopg2.Error: If query execution fails
    """
    try:
        logger.info(f"Executing query: {query}")
        with connection.cursor() as cursor:
            cursor.execute(query)
            results = cursor.fetchall()
            logger.info(f"Query executed successfully, returned {len(results)} rows")
            return results
            
    except psycopg2.Error as e:
        logger.error(f"Query execution failed: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error executing query: {e}")
        raise
    finally:
        try:
            connection.close()
            logger.info("Database connection closed")
        except Exception:
            pass  # Ignore connection close errors
