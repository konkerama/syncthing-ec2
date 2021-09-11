#!/bin/bash
set -e

# init.sh
# Description: One time set up of configuration parameters required for the deployment/runtime 
#
# Inputs:
#   -e <value> : Specify the environment name (used for naming convention). If not specified "dev" is used. 
#   -s <value> : S3 Bucket name (to be used for Terraform state and artifacts). Creates an SSM Parameter with this value (to be referenced by other scripts)
#   -u <value> : Username for Syncthing GUI. Creates an SSM Parameter with this value (to be referenced by other scripts)
#   -p <value> : Password for Syncthing GUI. Creates an SSM Parameter with this value (to be referenced by other scripts)
#   -i <value> : Your local Syncthing device-id with which you want to pair your EC2. Creates an SSM Parameter with this value (to be referenced by other scripts)
#   -n <value> : Your local Syncthing device-name with which you want to pair your EC2. Creates an SSM Parameter with this value (to be referenced by other scripts)

export TF_VAR_environment="dev"
source ./terraform-manifests/terraform.tfvars

while getopts e:s:u:p:i:n: option
  do
  case "${option}" in
    e) export TF_VAR_environment=${OPTARG};;
    s) export TF_VAR_s3_bucket=${OPTARG};;
    u) USERNAME=${OPTARG};;
    p) PASSWORD=${OPTARG};;
    i) LOCAL_DEVIDE_ID=${OPTARG};;
    n) LOCAL_DEVICE_NAME=${OPTARG};;
  esac
done

echo "Creating S3 Bucket SSM Parameter"
aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/s3_bucket_name" --value ${TF_VAR_s3_bucket} --type SecureString --overwrite

echo "Creating GUI Username SSM Parameter"
aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/gui/username" --value ${USERNAME} --type SecureString --overwrite

echo "Creating GUI Password SSM Parameter"
aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/gui/password" --value ${PASSWORD} --type SecureString --overwrite

echo "Creating Local Syncthing Device SSM Parameter"
LOCAL_DEVICE=$(jq -n --arg id "$LOCAL_DEVIDE_ID" --arg name "$LOCAL_DEVICE_NAME" '{"device_id": $id, "device_name": $name}')
aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/local_device" --value "${LOCAL_DEVICE}" --type SecureString --overwrite
