import os
import json
import boto3
import psycopg2
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    # Initialize clients
    ssm_client = boto3.client('ssm')
    sts_client = boto3.client('sts')
    
    try:
        # Get parameters from Parameter Store
        db_params = get_parameters_from_ssm(ssm_client)
        
        # Assume role in Account B
        assumed_role = assume_cross_account_role(sts_client)
        
        # Create RDS client with assumed role credentials
        rds_client = create_rds_client(assumed_role)
        
        # Get RDS endpoint
        db_endpoint = get_rds_endpoint(rds_client, db_params['db_instance_identifier'])
        
        # Connect to database
        connection = connect_to_database(db_endpoint, db_params)
        
        # Execute query
        result = execute_query(connection, "SELECT version();")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully connected to RDS',
                'result': result
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }

def get_parameters_from_ssm(ssm_client):
    """Retrieve database parameters from Parameter Store"""
    parameters = {}
    param_names = [
        '/myapp/db/username',
        '/myapp/db/password',
        '/myapp/db/database',
        '/myapp/db/instance_identifier'
    ]
    
    response = ssm_client.get_parameters(
        Names=param_names,
        WithDecryption=True
    )
    
    for param in response['Parameters']:
        key = param['Name'].split('/')[-1]
        parameters[f'db_{key}'] = param['Value']
    
    return parameters

def assume_cross_account_role(sts_client):
    """Assume role in Account B"""
    account_b_id = os.environ['ACCOUNT_B_ID']
    role_name = 'CrossAccountRDSAccessRole'
    
    response = sts_client.assume_role(
        RoleArn=f'arn:aws:iam::{account_b_id}:role/{role_name}',
        RoleSessionName='LambdaRDSAccess'
    )
    
    return response['Credentials']

def create_rds_client(credentials):
    """Create RDS client with assumed role credentials"""
    return boto3.client(
        'rds',
        aws_access_key_id=credentials['AccessKeyId'],
        aws_secret_access_key=credentials['SecretAccessKey'],
        aws_session_token=credentials['SessionToken']
    )

def get_rds_endpoint(rds_client, db_instance_identifier):
    """Get RDS instance endpoint"""
    response = rds_client.describe_db_instances(
        DBInstanceIdentifier=db_instance_identifier
    )
    
    return response['DBInstances'][0]['Endpoint']['Address']

def connect_to_database(endpoint, db_params):
    """Connect to PostgreSQL database"""
    return psycopg2.connect(
        host=endpoint,
        port=5432,
        database=db_params['db_database'],
        user=db_params['db_username'],
        password=db_params['db_password']
    )

def execute_query(connection, query):
    """Execute a query and return results"""
    with connection.cursor() as cursor:
        cursor.execute(query)
        return cursor.fetchall()
