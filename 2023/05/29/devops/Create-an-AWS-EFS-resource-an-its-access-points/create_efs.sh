#!/bin/sh

# Set the input env vars
AWS_PROFILE=myProfile
AWS_REGION=us-west-2
CLUSTER_NAME=myCluster

# Set the output env vars
MOUNT_TARGET_GROUP_NAME=mySG4EFS
MOUNT_TARGET_GROUP_DESC="NFS access to EFS from EKS worker nodes"
EFS_NAME=myEfsName

# Get eks cluster's VPC ID.
VPC_ID=$(aws eks describe-cluster --profile $AWS_PROFILE --region $AWS_REGION --name $CLUSTER_NAME \
        --query "cluster.resourcesVpcConfig.vpcId" --output text)
echo "The $CLUSTER_NAME includes the VPC $VPC_ID"

# Get the subnets's CIDR in the VPC.
CIDR_BLOCK=$(aws ec2 describe-vpcs --profile $AWS_PROFILE --region $AWS_REGION \
            --vpc-ids $VPC_ID --query "Vpcs[].CidrBlock" --output text)
echo "The CIDR blocks in the $VPC_ID : $CIDR_BLOCK"

# Create SG for EFS
# ------------
# MOUNT_TARGET_GROUP_ID=YOUR_EXISTED_SG_ID
MOUNT_TARGET_GROUP_ID=$(aws ec2 create-security-group --profile $AWS_PROFILE --region $AWS_REGION \
                    --group-name $MOUNT_TARGET_GROUP_NAME \
                    --description "$MOUNT_TARGET_GROUP_DESC" \
                    --vpc-id $VPC_ID \
                    | jq --raw-output '.GroupId')

# Set up the ingress rule for NFS
aws ec2 authorize-security-group-ingress --profile $AWS_PROFILE --region $AWS_REGION \
  --group-id $MOUNT_TARGET_GROUP_ID --protocol tcp --port 2049 --cidr $CIDR_BLOCK
# ------------

# Create EFS. 
# ------------
FILE_SYSTEM_ID=$(aws efs create-file-system --profile $AWS_PROFILE --region $AWS_REGION \
  --performance-mode generalPurpose --throughput-mode bursting \
  --tags Key=Name,Value=$EFS_NAME \
  --backup --encrypted --creation-token "$EFS_NAME"_0 | jq --raw-output '.FileSystemId')
echo "The EFS $FILE_SYSTEM_ID is created."
# ------------
# aws efs describe-file-systems --file-system-id $FILE_SYSTEM_ID

# Find out the public subtnets from the subnets of the eks cluster.
eksSubnetIds=($(aws eks describe-cluster --profile $AWS_PROFILE --region $AWS_REGION \
                --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.subnetIds" \
                --output text))
echo "The eks cluster $CLUSTER_NAME VPC $VPC_ID includes the subnets: $eksSubnetIds"

# 2) find the internet GW
IGW_ID=$(aws ec2 describe-internet-gateways  --profile $AWS_PROFILE --region $AWS_REGION \
        --filters Name=attachment.vpc-id,Values=${VPC_ID} \
        --query "InternetGateways[].InternetGatewayId" \
        | jq -r '.[0]')
echo "The internet gateway in the VPC $VPC_ID is $IGW_ID"
if [ "null" = "$IGW_ID" ] ; then
  echo "Can't find public IGW in VPN, exit ..."
fi

# 3) find public subnets and create mount target on them.
for subnetId in ${eksSubnetIds[@]}
  do
      echo "Check the subnet " $subnetId
      # 根据subnet相关的route-table信息，得到这个subnet的igw。
      IGW_IN_ROUTS=$(aws ec2 describe-route-tables --profile $AWS_PROFILE --region $AWS_REGION  \
                    --filter Name=association.subnet-id,Values=$subnetId \
                    --query "RouteTables[].Routes[]" \
                    | jq -r '.[] | select(.DestinationCidrBlock=="0.0.0.0/0") | .GatewayId')
      if [ -z $IGW_IN_ROUTS -o "null" = $IGW_IN_ROUTS ] ;  then
        echo "The subnet $subnetId is a private subnet."
      else
        echo "The subnet $subnetId is a public subnet. $IGW_ID $IGW_IN_ROUTS" 
        if [ "$IGW_ID" = "$IGW_IN_ROUTS" ] ; then
          echo "Creating the mount target in the subnet $subnetId."
          aws efs create-mount-target --profile $AWS_PROFILE --region $AWS_REGION \
                                      --file-system-id $FILE_SYSTEM_ID \
                                      --subnet-id $subnetId \
                                      --security-groups $MOUNT_TARGET_GROUP_ID
        elif [ "null" != "$IGW_IN_ROUTS" ] ; then
            echo "WARNING: The IGW id in routes does not equal with the one in VPC!"
        fi
      fi
  done


