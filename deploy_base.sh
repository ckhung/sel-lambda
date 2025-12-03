AWS_REGION="ap-northeast-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr create-repository --repository-name selenium-base-repo --image-tag-mutability MUTABLE
echo $AWS_ACCOUNT_ID
ECR_URI="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/selenium-lambda"
aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_URI
docker tag selenium-base-image:latest $ECR_URI:latest
docker push $ECR_URI:latest

