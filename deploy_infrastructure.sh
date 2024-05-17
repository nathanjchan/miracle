#!/bin/bash

# Load environment variables from .env file
export $(cat .env | xargs)

# Initialize Terraform
terraform init

# Plan Terraform deployment
terraform plan

# Apply Terraform deployment
terraform apply -auto-approve
