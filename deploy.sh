#!/bin/bash
set -e
# deploy.sh
# Description: Creating, updating or destroying the AWS Infrastructure. 
#              In the case of Creating/Updating it will also print usefull information about the created instance (synthing id/name, public ip, syncthing gui url)
#
# Inputs:
#   -e <value> : Specify the environment name (used for naming convention). If not specified "dev" is used. 
#   -d         : (Optional) Performs terraform destroy to remove the infrastructure, if not defined a terraform apply is performed.

cd terraform-manifests/
# read terraform varialbes and set default environment variable (dev)
export TF_VAR_environment="dev"

while getopts de: option
  do
  case "${option}" in
    e) export TF_VAR_environment=${OPTARG};;
    d) DESTROY=true;;
    *) echo "usage: $0 [-d] [-e]" >&2
       exit 1 ;;
  esac
done

# shellcheck disable=SC1091,SC1090
source "./envs/${TF_VAR_environment}.tfvars"

# read s3 bucket name (set in init.sh) and aws region
# shellcheck disable=SC2154
TF_VAR_s3_bucket=$(aws ssm get-parameter  --name "/${resource_name}/${TF_VAR_environment}/s3_bucket_name" \
                                          --with-decryption \
                                          --query "Parameter.Value" \
                                          --output text)
export TF_VAR_s3_bucket
TF_VAR_aws_region=$(aws configure get region --profile default)
export TF_VAR_aws_region

aws s3 cp ./../scripts/docker-compose.yml "s3://${TF_VAR_s3_bucket}/artifacts/${TF_VAR_environment}/"

# run terraform commands
terraform init  -reconfigure \
                -backend-config="bucket=${TF_VAR_s3_bucket}" \
                -backend-config="key=tfstate/${resource_name}/${TF_VAR_environment}/terraform.tfstate" \
                -backend-config="region=${TF_VAR_aws_region}"
terraform validate
export TF_CLI_ARGS="-var-file=envs/${TF_VAR_environment}.tfvars"

# depending on input either create/update or destroy resources
# shellcheck disable=SC2086
if [ ${DESTROY} ] ; then
  echo "Destroying infrastructure"
  terraform destroy --auto-approve
else
  terraform plan
  echo "Applying infrastructure"
  terraform apply --auto-approve
  unset TF_CLI_ARGS
  # if creating or updating the resources wait for the user data provisioning to finish and then diplay relevant information
  # one of the last steps of user-data.sh it will create/update an SSM parameter with the following json document
  # {
  #   "deviceID": "<syncthing-device-id>",
  #   "name": "<synthing-device-name>",
  #   "public_ip": "<ec2-public-ip>"
  # }
  # since the ec2 public ip value is already know (from terraform outputs), the bellow code continiously polls the ssm api until it the 2 public ips have the same value
  # ones they have the same value the relevant information are printed

  SSM_PARAMETER_DEVICE_INFO=$(aws ssm get-parameter --name "/${resource_name}/${TF_VAR_environment}/device_info" \
                                                    --with-decryption \
                                                    --query "Parameter.Value" \
                                                    --output text)

  # shellcheck disable=SC2154
  if [ "$connect_to_tailscale" = "true" ]; then
    HOST_NAME=$resource_name-$TF_VAR_environment-ec2
  else
    HOST_NAME=$(terraform output -raw ec2_public_ip)
  fi

  # echo "Syncthing EC2 Instance Information:"
  echo "${SSM_PARAMETER_DEVICE_INFO}" | jq .
  echo "To connect to the syncthing web gui visit: https://${HOST_NAME}:8384"
fi

cd ..
