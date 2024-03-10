#!/bin/bash

# Author: Chethan

# Executing in the debug mode
set -x

# Get the AWS account id
aws_account_id=$(aws sts get-caller-identity --query 'Account' --output text)

echo $aws_account_id

# Setting variables
aws_region="us-east-1"
bucket_name="event-demo-bucket-111111"
lambda_function="s3-lambda-function"
role_name="s3-lambda-sns"
email_id="chethanreddy.mp@gmail.com"

# Create the IAM role for the project
iam_role_response=$(aws iam create-role --role-name s3-lambda-sns --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Action": "sts:AssumeRole",
    "Effect": "Allow",
    "Principal": {
      "Service": [
         "lambda.amazonaws.com",
         "s3.amazonaws.com",
         "sns.amazonaws.com"
      ]
    }
  }]
}')
# Getting role ARN 
role_arn=$(echo "$iam_role_response" | jq -r '.Role.Arn')

echo $role_arn

# Attach policies to the IAM role
aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
aws iam attach-role-policy --role-name "$role_name" --policy-arn arn:aws:iam::aws:policy/AmazonSNSFullAccess

# Create S3 bucket
bucket_response=$(aws s3api create-bucket --bucket "$bucket_name" --region "$aws_region")

echo "Bucket name: $bucket_response"

# Copy the file to S3
aws s3 cp ./dummy.txt s3://"$bucket_name"/dummy.txt

# Zip Lambda function
zip -r s3-lambda-function.zip ./s3-lambda-function

sleep 5

# Create Lambda function
aws lambda create-function \
  --region "$aws_region" \
  --function-name $lambda_function \
  --runtime "python3.8" \
  --handler "s3-lambda-function/s3-lambda-function.lambda_handler" \
  --memory-size 128 \
  --timeout 30 \
  --role "arn:aws:iam::$aws_account_id:role/$role_name" \
  --zip-file "fileb://./s3-lambda-function.zip"

# Add permissions to S3 bucket to invoke Lambda
aws lambda add-permission \
  --function-name "$lambda_function" \
  --statement-id "s3-lambda-sns" \
  --action "lambda:InvokeFunction" \
  --principal s3.amazonaws.com \
  --source-arn "arn:aws:s3:::$bucket_name"

lambdafunctionarn="arn:aws:lambda:us-east-1:$aws_account_id:function:s3-lambda-function"

# Configure S3 bucket notification to trigger Lambda
aws s3api put-bucket-notification-configuration \
  --region "$aws_region" \
  --bucket "$bucket_name" \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [{
        "LambdaFunctionArn": "'"$lambdafunctionarn"'",
        "Events": ["s3:ObjectCreated:*"]
    }]
}'

# Create SNS topic
topic_arn=$(aws sns create-topic --name s3-lambda-sns | jq -r '.TopicArn')

echo "Topic ARN: $topic_arn"

# Subscribe email to SNS topic
aws sns subscribe --topic-arn "$topic_arn" --protocol email --notification-endpoint "$email_id"

# Publish message to SNS topic
aws sns publish --message "Hello from Chethan AWS" --topic-arn "$topic_arn" --subject "A new object created in S3 bucket"

