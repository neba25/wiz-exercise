#!/bin/bash
# Usage: ./build_and_push.sh <your-name> <ecr-repo-url> <aws-region>
set -euxo pipefail

NAME="$1"
ECR_REPO="$2"
REGION="${3:-us-east-1}"

cd "$(dirname "$0")/../app"

echo "Building image..."
docker build --build-arg NAME="$NAME" -t wiz-exercise-app:latest .

echo "--- Validating wizexercise.txt exists in the built image ---"
docker run --rm wiz-exercise-app:latest cat /wizexercise.txt

echo "Logging into ECR..."
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$(echo "$ECR_REPO" | cut -d/ -f1)"

docker tag wiz-exercise-app:latest "$ECR_REPO:latest"
docker push "$ECR_REPO:latest"

echo "Done. Image pushed to $ECR_REPO:latest"
