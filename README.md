# Syncthing EC2
## Overview 
This solution tries to simplify the creation and initial setup of a Syncthing node on the Public Cloud (AWS). It uses Terraform to provision the necessary resources on AWS. The Syncthing software is installed in a Docker container on the created EC2 (using `docker-compose`). After the Syncthing container is up and running the [Synthing API](https://docs.syncthing.net/dev/rest.html) is used to retrieve relevant information (device id & name), set up GUI username/password and automatically pair with existing Syncthing device.

## Prerequisites
This project assumes that you are already familiar and using Syncthing on your local devices. If you want more information you can check the [Getting Started Guide](https://docs.syncthing.net/intro/getting-started.html)

Technical requirements:
* AWS Account and working `aws-cli`
* Terraform ([Installation Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli))
* Create an S3 Bucket on your account (to be used for Terraform State and Artifacts)


## How to deploy
1. Run `init.sh` (one-time) to perform the initial configuration:

``` bash 
./init.sh \
  -e <environment-name> \
  -s <s3-bucket-name> \
  -u <syncthing-gui-username> \
  -p <syncthing-gui-password> \
  -i <local-syncthing-device-id> \
  -n <local-syncthing-device-name> \
```
Argument Explanation:

| Argument Name                      | Description                                                  | Example                                                      |
| ---------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `-e <environment-name>`            | (Mandatory) Specify the environment name (used for naming convention). If not specified "dev" is used. | `dev`                                                        |
| `-s <s3-bucket-name>`              | (Mandatory) S3 Bucket name (to be used for Terraform state and artifacts). Creates an SSM Parameter with this value (to be referenced by other scripts) | `my-s3-bucket-name`                                          |
| `-u <syncthing-gui-username>`      | (Mandatory) Username for Syncthing GUI. Creates an SSM Parameter with this value (to be referenced by other scripts) | `myusername`                                                 |
| `-p <syncthing-gui-password>`      | (Mandatory) Password for Syncthing GUI. Creates an SSM Parameter with this value (to be referenced by other scripts) | `mysecurepassword`                                           |
| `-i <local-syncthing-device-id>`   | (Mandatory) Your local Syncthing device-id with which you want to pair your EC2. Creates an SSM Parameter with this value (to be referenced by other scripts) | `MFZWI3D-BONSGYC-YLTMRWG-C43ENR5-QXGZDMM-FZWI3DP-BONSGYY-LTMRWAD` |
| `-n <local-syncthing-device-name>` | (Mandatory) Your local Syncthing device-name with which you want to pair your EC2. Creates an SSM Parameter with this value (to be referenced by other scripts) | `my-local-device`                                            |

2. Review `terraform-manifests/terraform.tfvars`

This is the file that provides the read of the input to Terraform (besides the ones already set on `init.sh`) 

Argument Explanation:

| Argument Name         | Type    | Description                                                  | Example     |
| --------------------- | ------- | ------------------------------------------------------------ | ----------- |
| `resource_name`       | String  | Naming convention for the AWS Resources to be created        | `syncthing` |
| `instance_type`       | String  | EC2 Instance Type. Check the [AWS Documentation](https://aws.amazon.com/ec2/instance-types/) for more information. | `t3.nano`   |
| `volume_size`         | Number  | EC2 Volume Size (in GBs)                                     | `10`        |
| `connect_to_instance` | Boolean | Configure the necessary Security Group rules to connect to the created ec2 instance. If set to `true` Terraform will create an EC2 Security Group rule to allow the local machine to access the EC2 instance on port 8384 (used by Syncthing). If set to `false` all inbound communications to the EC2 Instance are blocker (for increased security) | `true`      |

3. Finally you need to run the following command to create/update or destroy (in subsequent call) your infrastructure:

``` bash
./deploy.sh -e <environment-name>
```
Argument Explanation:

| Argument Name           | Description                                                  | Example |
| ----------------------- | ------------------------------------------------------------ | ------- |
| `-e <environment-name>` | (Mandatory) Specify the environment name (used for naming convention). If not specified "dev" is used. | `dev`   |
| `-d`                    | (Optional) Performs Terraform destroy to remove the infrastructure, if not defined a Terraform apply is performed. |         |

This final command will trigger the Terraform manifests which will create:

* EC2 Security Group
* EC2 IAM Role/Instance Profile
* EC2 Instance

After running this command, you should see your terminal an output similar to the following:

```
Syncthing EC2 Instance Information:
{
  "deviceID": "MFZWI3D-BONSGYC-YLTMRWG-C43ENR5-QXGZDMM-FZWI3DP-BONSGYY-LTMRWAD",
  "name": "syncthing-ec2",
  "public_ip": "1.2.3.4"
}
To connect to the syncthing web gui visit: https://1.2.3.4:8384
```

Here you can find the Synthing device id of the instance that was just created and the public ip. By clicking the link you can also visit the Synthing web GUI. You will be asked for a username and password, you need to provide the same ones you provided in the `init.sh`.

Finally, if you open your web GUI of your existing device (same you provided in `init.sh`) you should see a pairing request from the EC2 you just created, like the following:

![pairing-request](imgs/pairing-request.png)

Note that in the EC2 configuration the Local Device is configured with `autoAcceptFolders = true` meaning that you can directly share a folder from the local Device, and the files will be automatically synced with the EC2. 

## TO-DO List:
* Implement fine-grained IAM Role permissions
* Add multiple local devices to syncthing configuration
* Stream logs to Cloudwatch
  * Create Cloudwatch log group
  * Stream `cloud-init-output` & docker container logs

# License
Licensed under the Apache License, Version 2.0 ([LICENSE](LICENSE)
or http://www.apache.org/licenses/LICENSE-2.0).

## Contribution
Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be licensed as above, without any additional terms or conditions.
