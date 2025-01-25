#!/bin/sh


AWS_PROFILE=myProfile
AWS_REGION=us-west-2
ACCESS_POING_NAME=myAP
FILE_SYSTEM_ID=YOUR_EFS_ID
AP_USER='{"Uid": 123, "Gid": 123, "SecondaryGids": [20]}'
AP_ROOT_DIR='/myapp/logs,CreationInfo={OwnerUid=123,OwnerGid=123,Permissions=0755}'

aws efs create-access-point --profile $AWS_PROFILE --region $AWS_REGION  \
--tags Key=name,Value=$ACCESS_POING_NAME \
--client-token "$ACCESS_POING_NAME" \
--file-system-id $FILE_SYSTEM_ID \
--posix-user $AP_USER \
--root-directory Path=$AP_ROOT_DIR

# aws efs delete-access-point --profile $AWS_PROFILE --region $AWS_REGION  --access-point-id $AP_ID
