#!/bin/bash
set -e

AWS_REGION="ap-northeast-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

APP_FILE=$1
EXECUTION_ROLE_ARN="arn:aws:iam::$AWS_ACCOUNT_ID:role/lambda_worker"

FUNCTION_NAME=${APP_FILE%.*}
REPO_NAME=selenium-lambda

BASE_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:latest"
THIN_IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${FUNCTION_NAME}:latest"

# Create a temporary Dockerfile for the thin layer
cat <<EOF > Dockerfile.${FUNCTION_NAME}
FROM ${BASE_IMAGE_URI}
COPY ${APP_FILE} ./
CMD ["${FUNCTION_NAME}.lambda_handler"]
EOF

# Build the thin image
docker build -t ${REPO_NAME} -f Dockerfile.${FUNCTION_NAME} .

# Authenticate Docker to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin ${THIN_IMAGE_URI}

# Tag and push the thin image
docker tag ${REPO_NAME}:latest ${THIN_IMAGE_URI}
docker push ${THIN_IMAGE_URI}

# Check if the Lambda function already exists
if aws lambda get-function --function-name ${FUNCTION_NAME} > /dev/null 2>&1; then
    echo "Updating existing function: ${FUNCTION_NAME}"
    aws lambda update-function-code \
        --function-name ${FUNCTION_NAME} \
        --image-uri ${THIN_IMAGE_URI}
else
    echo "Creating new function: ${FUNCTION_NAME}"
    aws lambda create-function \
        --function-name ${FUNCTION_NAME} \
        --package-type Image \
        --code ImageUri=${THIN_IMAGE_URI} \
        --role ${EXECUTION_ROLE_ARN} \
        --memory-size 4096 \
        --timeout 600
fi

rm Dockerfile.${FUNCTION_NAME}
aws ecr describe-images --repository-name ${REPO_NAME} --image-ids imageTag=latest | jq '.imageDetails[0].imageDigest' | grep -Po '\b[0-9a-f]{64}\b'
aws lambda get-function --function-name ${FUNCTION_NAME} | jq '.Configuration.CodeSha256' | grep -Po '\b[0-9a-f]{64}\b'
