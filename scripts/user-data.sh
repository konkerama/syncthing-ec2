#!/bin/bash

# user-data.sh
# Description: Bootstap script for the EC2 Instance. Actions performed include:
#                - Installation and set up of docker and docker-compose
#                - Retrieveal of docker-compose.yml from previously uploaded S3 Bucket
#                - Creation of the container
#                - Set up of GUI username/password using information present in SSM Parameter Store
#                - Retrieval of usefull information (Synching device id & name)
#                - Set up pairing with existing local synthing device

# install docker & docker-compose
sudo yum update -y  
sudo yum install -y docker
sudo yum install -y jq
sudo systemctl enable docker
sudo systemctl start docker

sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# set aws cli region
aws configure set region $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

# get instance id
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# get s3_bucket resource_name & environment
RESOURCE_NAME=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --query "Reservations[0].Instances[0].Tags[?Key=='resource_name'].Value" --output text)
ENVIRONMENT=$(aws ec2 describe-instances --instance-ids ${INSTANCE_ID} --query "Reservations[0].Instances[0].Tags[?Key=='environment'].Value" --output text)

S3_BUCKET_NAME=$(aws ssm get-parameter --name /${RESOURCE_NAME}/${ENVIRONMENT}/s3_bucket_name --with-decryption --query "Parameter.Value" --output text)

# copy docker compose to working directory
aws s3 cp s3://${S3_BUCKET_NAME}/artifacts/docker-compose.yml .

# run container
docker-compose up -d

echo "Sleeping for 5 seconds to allow the container to be configured..." && sleep 5

echo "Retrieve Syncthing API Key"
XML_FILE="/data/st-sync/config/config.xml"
SYNCTHING_API_KEY=$(xmllint --xpath 'string(/configuration/gui/apikey)' $XML_FILE)

echo "Put Syncthing API Key on SMM Parameter Store, Parameter Name: /${RESOURCE_NAME}/${ENVIRONMENT}/api_key"
aws ssm put-parameter --name "/${RESOURCE_NAME}/${ENVIRONMENT}/api_key" --value ${SYNCTHING_API_KEY} --type SecureString --overwrite

echo "--Updating Syncthing GUI username and password--"
echo "Reading Syncthing username and password from SSM Parameter Store"
USERNAME=$(aws ssm get-parameter --name /${RESOURCE_NAME}/${ENVIRONMENT}/gui/username --with-decryption --query "Parameter.Value" --output text)
PASSWORD=$(aws ssm get-parameter --name /${RESOURCE_NAME}/${ENVIRONMENT}/gui/password --with-decryption --query "Parameter.Value" --output text)

echo "Retrieving current Syncthing config"
curl -s -H "X-API-Key: ${SYNCTHING_API_KEY}" localhost:8384/rest/config > config.json

echo "Modifying the username and password json fields"
jq '.gui.user = $username' config.json --arg username "${USERNAME}" > tmp.json && mv tmp.json config.json
jq '.gui.password = $password' config.json --arg password "${PASSWORD}" > tmp.json && mv tmp.json config.json

echo "Pushing new Syncthing config"
curl -s -w "%{http_code}\n" -X PUT -H "X-API-Key: ${SYNCTHING_API_KEY}" localhost:8384/rest/config -H "Content-Type: application/json" -d @config.json
rm config.json

echo "Identifying if restart is required"
curl -s -H "X-API-Key: ${SYNCTHING_API_KEY}" localhost:8384/rest/config/restart-required

echo "-- Adding Current Devices --"
echo "Retrieving current Syncthing config"
curl -s -H "X-API-Key: ${SYNCTHING_API_KEY}" localhost:8384/rest/config > config.json

echo "Extracting local device info and pushing it to SSM Parameter Store, Parameter Name: /${RESOURCE_NAME}/${ENVIRONMENT}/device_info"
jq '.devices[0]' config.json > device.json
jq 'with_entries(select([.key] | inside(["deviceID", "name"])))' device.json > device-info.json
DEVICE_INFO=$(jq '. += { "public_ip": $public_ip }' --arg public_ip "${INSTANCE_PUBLIC_IP}" device-info.json)
aws ssm put-parameter --name "/${RESOURCE_NAME}/${ENVIRONMENT}/device_info" --value "${DEVICE_INFO}" --type SecureString --overwrite

# modify deviceID, name & autoAcceptFolders
echo "Reading existing device name and id"
EXTERNAL_DEVICE_ID="OF33D6H-IRS2J5A-SDGDSGI-7GHTX4F-TMS764K-NBH2RB4-KS3X3OE-TY7JNAL"
EXTERNAL_DEVICE_NAME="thinkpad"

echo "Adding existing devices to config.json"
jq '. + {deviceID:$device_id, name:$device_name, autoAcceptFolders:true}' device.json --arg device_id "${EXTERNAL_DEVICE_ID}" --arg device_name "${EXTERNAL_DEVICE_NAME}" > tmp.json && mv tmp.json device.json
jq --argjson device "$(<device.json)" '.devices += [$device]' config.json > tmp.json && mv tmp.json config.json

echo "Pushing new Syncthing config"
curl -s -w "%{http_code}\n" -X PUT -H "X-API-Key: ${SYNCTHING_API_KEY}" localhost:8384/rest/config -H "Content-Type: application/json" -d @config.json

echo "Identifying if restart is required"
curl -s -H "X-API-Key: ${SYNCTHING_API_KEY}" localhost:8384/rest/config/restart-required