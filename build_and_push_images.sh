#!/bin/bash

# Load environment variables from .env file
export $(cat .env | xargs)

# Variables
AWS_ACCOUNT_ID=$TF_VAR_aws_account_id
REGION=$TF_VAR_aws_region
FRONTEND_REPO=frontend
WEBSCRAPER_REPO=webscraper

# Authenticate Docker to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Create ECR repositories if they don't exist
aws ecr describe-repositories --repository-names $FRONTEND_REPO --region $REGION || aws ecr create-repository --repository-name $FRONTEND_REPO --region $REGION
aws ecr describe-repositories --repository-names $WEBSCRAPER_REPO --region $REGION || aws ecr create-repository --repository-name $WEBSCRAPER_REPO --region $REGION

# Build Docker images for the correct platform
docker build --platform linux/amd64 -t $FRONTEND_REPO ./frontend
docker build --platform linux/amd64 -t $WEBSCRAPER_REPO ./webscraper

# Tag Docker images
docker tag $FRONTEND_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$FRONTEND_REPO:latest
docker tag $WEBSCRAPER_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$WEBSCRAPER_REPO:latest

# Push Docker images
docker push $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$FRONTEND_REPO:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$WEBSCRAPER_REPO:latest
