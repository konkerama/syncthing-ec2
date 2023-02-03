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

while getopts e:s:u:p:i:n:t: option
  do
  case "${option}" in
    e) export TF_VAR_environment=${OPTARG};;
    s) export TF_VAR_s3_bucket=${OPTARG};;
    u) SYNCTHING_USERNAME=${OPTARG};;
    p) PASSWORD=${OPTARG};;
    i) LOCAL_DEVIDE_ID=${OPTARG};;
    n) LOCAL_DEVICE_NAME=${OPTARG};;
    t) TS_TOKEN=${OPTARG};;
    *) echo "usage: $0 [-e] [-s] [-u] [-p] [-i] [-n] [-t]" >&2
       exit 1 ;;
  esac
done

# shellcheck disable=SC1091,SC1090
source "./terraform-manifests/envs/${TF_VAR_environment}.tfvars"

if [ -n "$TF_VAR_s3_bucket" ]; then 
  echo "Creating S3 Bucket SSM Parameter"
  # shellcheck disable=SC2154
  aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/s3_bucket_name" --value "${TF_VAR_s3_bucket}" --type SecureString --overwrite
fi
if [ -n "$SYNCTHING_USERNAME" ]; then 
  echo "Creating GUI Username SSM Parameter"
  aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/gui/username" --value "${SYNCTHING_USERNAME}" --type SecureString --overwrite
fi 

if [ -n "$PASSWORD" ]; then 
  echo "Creating GUI Password SSM Parameter"
  aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/gui/password" --value "${PASSWORD}" --type SecureString --overwrite
fi

if [ -n "$LOCAL_DEVIDE_ID" ] && [ -n "$LOCAL_DEVICE_NAME" ]; then 
  echo "Creating Local Syncthing Device SSM Parameter"
  LOCAL_DEVICE=$(jq -n --arg id "$LOCAL_DEVIDE_ID" --arg name "$LOCAL_DEVICE_NAME" '{"device_id": $id, "device_name": $name}')
  aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/local_device" --value "${LOCAL_DEVICE}" --type SecureString --overwrite
fi

if [ -n "$TS_TOKEN" ]; then 
  echo "Creating Tailscale Token SSM Parameter"
  aws ssm put-parameter --name "/${resource_name}/${TF_VAR_environment}/tailscale/token" --value "${TS_TOKEN}" --type SecureString --overwrite
fi