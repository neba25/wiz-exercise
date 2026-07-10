#!/bin/bash
# Installs the AWS Load Balancer Controller so the Ingress resource in
# k8s/05-ingress.yaml can provision a real internet-facing ALB.
# Prereqs: helm, kubectl configured against the EKS cluster, eksctl.
set -euxo pipefail

CLUSTER_NAME="$1"
REGION="${2:-us-east-1}"

eksctl utils associate-iam-oidc-provider --cluster "$CLUSTER_NAME" --region "$REGION" --approve

curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json || true

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn="arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
  --override-existing-serviceaccounts \
  --region "$REGION" \
  --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="$REGION"

echo "AWS Load Balancer Controller installed."
