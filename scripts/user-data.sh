#!/bin/bash

# user-data.sh
# Description: Bootstap script for the EC2 Instance. Actions performed include:
#                - Installation and set up of docker and docker-compose
#                - Retrieveal of docker-compose.yml from previously uploaded S3 Bucket
#                - Creation of the container
#                - Set up of GUI username/password using information present in SSM Parameter Store
#                - Retrieval of usefull information (Synching device id & name)
#                - Set up pairing with existing local synthing device
#                - (Optional) If selected add EC2 to the Tailscale Network
#                - (Optional) If selected reuse existing synchting configuration

# install docker
sudo yum update -y  
sudo yum install -y docker
sudo yum install -y jq
sudo systemctl enable docker
sudo systemctl start docker


DOCKER_CLI_PLUGINS_DIR=/usr/local/lib/docker/cli-plugins
sudo mkdir -p $DOCKER_CLI_PLUGINS_DIR/
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-armv7 -o $DOCKER_CLI_PLUGINS_DIR/docker-compose
sudo chmod +x $DOCKER_CLI_PLUGINS_DIR/docker-compose


TOKEN=$(curl --request PUT "http://169.254.169.254/latest/api/token" --header "X-aws-ec2-metadata-token-ttl-seconds: 3600")

# set aws cli region
# shellcheck disable=SC2046
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)
export AWS_REGION
aws configure set region "$AWS_REGION"

# get instance id
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

# get EC2 information
RESOURCE_NAME=$(aws ec2 describe-instances  --instance-ids "${INSTANCE_ID}" \
                                            --query "Reservations[0].Instances[0].Tags[?Key=='resource_name'].Value" \
                                            --output text)
export RESOURCE_NAME
ENVIRONMENT=$(aws ec2 describe-instances    --instance-ids "${INSTANCE_ID}" \
                                            --query "Reservations[0].Instances[0].Tags[?Key=='environment'].Value" \
                                            --output text)
export ENVIRONMENT
CREATE_CONFIG=$(aws ec2 describe-instances  --instance-ids "${INSTANCE_ID}" \
                                            --query "Reservations[0].Instances[0].Tags[?Key=='create_syncthing_config'].Value" \
                                            --output text)
export CREATE_CONFIG
CONNECT_TO_TAILSCALE=$(aws ec2 describe-instances   --instance-ids "${INSTANCE_ID}" \
                                                    --query "Reservations[0].Instances[0].Tags[?Key=='connect_to_tailscale'].Value" \
                                                    --output text)
export CONNECT_TO_TAILSCALE
INSTANCE_NAME=$(aws ec2 describe-instances  --instance-ids "${INSTANCE_ID}" \
                                            --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value" \
                                            --output text)
export INSTANCE_NAME

# Connect to tailscale
if [ "$CONNECT_TO_TAILSCALE" = "true" ]; then
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled
    INSTANCE_ENDPOINT="$INSTANCE_NAME"
    TAILSCALE_TOKEN=$(aws ssm get-parameter --name "/${RESOURCE_NAME}/${ENVIRONMENT}/tailscale/token" \
                                            --with-decryption \
                                            --query "Parameter.Value" \
                                            --output text)

    sudo tailscale up --hostname="$INSTANCE_ENDPOINT" --authkey="${TAILSCALE_TOKEN}" --ssh
else 
    INSTANCE_ENDPOINT=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

fi

# run container
mkdir /data/st-sync/config -p
chown 1000:1000 /data/st-sync/ -R

S3_BUCKET_NAME=$(aws ssm get-parameter  --name "/${RESOURCE_NAME}/${ENVIRONMENT}/s3_bucket_name" \
                                    --with-decryption \
                                    --query "Parameter.Value" \
                                    --output text)

if [ "$CREATE_CONFIG" = "false" ]; then
    echo "Grabbing config from ssm and s3"
    aws ssm get-parameter   --name "/${RESOURCE_NAME}/${ENVIRONMENT}/config/cert.pem" \
                            --with-decryption \
                            --query "Parameter.Value" \
                            --output text > /data/st-sync/config/cert.pem
    aws ssm get-parameter   --name "/${RESOURCE_NAME}/${ENVIRONMENT}/config/key.pem" \
                            --with-decryption \
                            --query "Parameter.Value" \
                            --output text > /data/st-sync/config/key.pem
    aws s3 cp "s3://${S3_BUCKET_NAME}/artifacts/${ENVIRONMENT}/config.xml" /data/st-sync/config/config.xml
fi

aws s3 cp "s3://${S3_BUCKET_NAME}/artifacts/${ENVIRONMENT}/docker-compose.yml" .

docker compose up -d

echo "Sleeping for 5 seconds to allow the container to be configured..." && sleep 5

echo "Retrieve Syncthing API Key"
XML_FILE="/data/st-sync/config/config.xml"
SYNCTHING_API_KEY=$(xmllint --xpath 'string(/configuration/gui/apikey)' $XML_FILE)

if [ "$CREATE_CONFIG" = "true" ]; then
    USERNAME=$(aws ssm get-parameter    --name "/${RESOURCE_NAME}/${ENVIRONMENT}/gui/username" \
                                        --with-decryption \
                                        --query "Parameter.Value" \
                                        --output text)

    echo "Put Syncthing API Key on SMM Parameter Store, Parameter Name: /${RESOURCE_NAME}/${ENVIRONMENT}/api_key"
    aws ssm put-parameter   --name "/${RESOURCE_NAME}/${ENVIRONMENT}/api_key" \
                            --value "${SYNCTHING_API_KEY}" \
                            --type SecureString \
                            --overwrite

    echo "--Updating Syncthing GUI username and password--"
    echo "Reading Syncthing username and password from SSM Parameter Store"
    USERNAME=$(aws ssm get-parameter    --name "/${RESOURCE_NAME}/${ENVIRONMENT}/gui/username" \
                                        --with-decryption \
                                        --query "Parameter.Value" \
                                        --output text)
    PASSWORD=$(aws ssm get-parameter    --name "/${RESOURCE_NAME}/${ENVIRONMENT}/gui/password" \
                                        --with-decryption \
                                        --query "Parameter.Value" \
                                        --output text)

    echo "Retrieving current Syncthing config"
    curl -s localhost:8384/rest/config \
            -H "X-API-Key: ${SYNCTHING_API_KEY}" > config.json

    echo "Modifying the username and password json fields"
    jq '.gui.user = $username' config.json \
        --arg username "${USERNAME}" > tmp.json && mv tmp.json config.json
    jq '.gui.password = $password' config.json \
        --arg password "${PASSWORD}" > tmp.json && mv tmp.json config.json

    echo "Pushing new Syncthing config"
    curl -s localhost:8384/rest/config \
        -X PUT \
        -w "%{http_code}\n" \
        -H "X-API-Key: ${SYNCTHING_API_KEY}"  \
        -H "Content-Type: application/json" \
        -d @config.json
    
    rm config.json

    echo "Identifying if restart is required"
    curl -s localhost:8384/rest/config/restart-required \
            -H "X-API-Key: ${SYNCTHING_API_KEY}" 

    echo "-- Adding Current Devices --"
    echo "Retrieving current Syncthing config"
    curl -s localhost:8384/rest/config \
            -H "X-API-Key: ${SYNCTHING_API_KEY}" > config.json

    # echo "Extracting local device info and pushing it to SSM Parameter Store, Parameter Name: /${RESOURCE_NAME}/${ENVIRONMENT}/device_info"
    jq '.devices[0]' config.json > device.json

    # modify deviceID, name & autoAcceptFolders
    echo "Reading existing device name and id"
    EXTRENAL_DEVICE=$(aws ssm get-parameter --name "/${RESOURCE_NAME}/${ENVIRONMENT}/local_device" \
                                            --with-decryption \
                                            --query "Parameter.Value" \
                                            --output text)
    EXTERNAL_DEVICE_ID=$(echo "$EXTRENAL_DEVICE" | jq .device_id --raw-output)
    EXTERNAL_DEVICE_NAME=$(echo "$EXTRENAL_DEVICE" | jq .device_name --raw-output)

    echo "Adding existing devices to config.json"
    jq '. + {deviceID:$device_id, name:$device_name, autoAcceptFolders:true}' device.json \
        --arg device_id "${EXTERNAL_DEVICE_ID}" \
        --arg device_name "${EXTERNAL_DEVICE_NAME}" > tmp.json && mv tmp.json device.json
    jq --argjson device "$(<device.json)" '.devices += [$device]' config.json > tmp.json && mv tmp.json config.json

    echo "Pushing new Syncthing config"
    curl -s localhost:8384/rest/config \
            -X PUT \
            -w "%{http_code}\n" \
            -H "X-API-Key: ${SYNCTHING_API_KEY}"  \
            -H "Content-Type: application/json" \
            -d @config.json

    echo "Identifying if restart is required"
    curl -s localhost:8384/rest/config/restart-required \
            -H "X-API-Key: ${SYNCTHING_API_KEY}" 
fi

echo "Extracting local device info and pushing it to SSM Parameter Store, Parameter Name: /${RESOURCE_NAME}/${ENVIRONMENT}/device_info"
DEVICE_ID=$(curl -s localhost:8384/rest/system/status \
                    -H "X-API-Key: ${SYNCTHING_API_KEY}" | jq .myID --raw-output)

DEVICE_INFO=$(jq    --null-input \
                    --arg deviceID "$DEVICE_ID" \
                    --arg name "$INSTANCE_NAME" \
                    --arg endpoint "$INSTANCE_ENDPOINT" \
                    '{"deviceID": $deviceID, "name": $name, "endpoint": $endpoint}')

aws ssm put-parameter   --name "/${RESOURCE_NAME}/${ENVIRONMENT}/device_info" \
                        --value "${DEVICE_INFO}" \
                        --type SecureString \
                        --overwrite
