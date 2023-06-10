#!/bin/bash
set -x
set -o errexit

# Creating an EKS Cluster from an EC2 Instance using EKSCTL
#
# Input parameters:
# appPrefix
# environment
# accountId
# keyId
#  

usage() {
echo "
Usage:
cluster.sh [options]
Options:
-a | --appPrefix                       Application prefix (amx-ppl-cc, amx-ivr, etc...)
-e | --envrionment                     Environment (des, q, prod)
-k | --keyARN                          Key ARN of KMS key used for envelope encryption of Kubernetes secrets
                                       e.g. arn:aws:kms:\${region}:\${accountId}:key/\${keyARN}
-p | --portalCidr                      Internal Portal CIDR
-r | --region                          AWS Region (us-east-1, us-east-2, etc...)
-i | --accountId                       AWS account id
-v | --vpcId                           VPC Id
     --cidrBlock                       VPC's CIDR Block
     --sharedNodeSg                    Shared Node Security Group
     --subnet1                         Application Subnet 1
     --subnet2                         Application Subnet 2
     --eksClusterVersion               EKS Cluster version
     --CloudWatchWriteAccessPolicyArn  e.g. arn:aws:iam::\${accountId}:policy/\${clusterName}-iam-p-cwtch-write
     --S3ReadWriteAccessPolicyArn      e.g. arn:aws:iam::\${accountId}:policy/\${clusterName}-iam-p-s3-read-write
     --SMKMSReadAccessPolicyArn        e.g. arn:aws:iam::\${accountId}:policy/\${clusterName}-iam-p-sm-kms-read
     --EksIamRoleArn                   Deployer EKS IAM Role ARN
                                         e.g. arn:aws:iam::\${accountId}:role/\${clusterName}-iam-rol-eks-deployer
     --CbEksIamRoleArn                 CodeBuild EKS IAM Role ARN
                                         e.g. arn:aws:iam::\${accountId}:role/AMX-PPL-CB-EKS-\${accountId}-\${region}
-x                                     Print command traces
" 1>&2
exit 1;
}

eksClusterVersion="1.24"

while getopts ":-:a:e:i:k:p:r:v:x" o; do
    case "${o}" in
        -) 
            case "${OPTARG}" in
                appPrefix)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    appPrefix=${val}
                    ;;
                environment)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    environment=${val}
                    ;;
                accountId)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    accountId=${val}
                    ;;
                keyARN)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    keyARN=${val}
                    ;;
                portalCidr)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    portalCidr=${val}
                    ;;
                region)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    region=${val}
                    ;;
                vpcId)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    vpcId=${val}
                    ;;
                cidrBlock)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    cidrBlock=${val}
                    ;;
                sharedNodeSg)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    sharedNodeSg=${val}
                    ;;
                subnet1)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    subnet1=${val}
                    ;;
                subnet2)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    subnet2=${val}
                    ;;
                eksClusterVersion)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    eksClusterVersion=${val}
                    ;;
                CloudWatchWriteAccessPolicyArn)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    CloudWatchWriteAccessPolicyArn=${val}
                    ;;
                S3ReadWriteAccessPolicyArn)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    S3ReadWriteAccessPolicyArn=${val}
                    ;;
                SMKMSReadAccessPolicyArn)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    SMKMSReadAccessPolicyArn=${val}
                    ;;
                EksIamRoleArn)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    EksIamRoleArn=${val}
                    ;;
                CbEksIamRoleArn)
                    val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    CbEksIamRoleArn=${val}
                    ;;
                *)
                    if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                        echo "Unknown option --${OPTARG}" >&2
                    fi
                    ;;
            esac;;
        a)
            appPrefix=${OPTARG}
            ;;
        e)
            environment=${OPTARG}
            ;;
        i)
            accountId=${OPTARG}
            ;;
        k)
            keyId=${OPTARG}
            ;;
        p)
            portalCidr=${OPTARG}
            ;;
        r)
            region=${OPTARG}
            ;;
        v)
            vpcId=${OPTARG}
            ;;
        x)
            set -x
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${appPrefix}" ] || [ -z "${environment}" ] || [ -z "${CloudWatchWriteAccessPolicyArn}" ] || [ -z "${S3ReadWriteAccessPolicyArn}" ] || [ -z "${SMKMSReadAccessPolicyArn}" ] || [ -z "${EksIamRoleArn}" ] || [ -z "${CbEksIamRoleArn}" ]
then
  echo "Missing main configuration attribute"
  exit 1;
fi

clusterNameLower="${appPrefix,,}-${environment,,}"
clusterNameUpper="${appPrefix^^}-${environment^^}"
namespace="${clusterNameLower}-ns"

## Introduction

# This document provides instructions on how to create an Amazon Elastic Kubernetes Service (EKS) cluster
# from an EC2 instance using EKSCTL. The EKS cluster will be private, with worker nodes only accessible
# within a virtual private cloud (VPC), and the EC2 instance will be in a private subnet. Access to the EC2
# instance will be provided through Amazon System Manager (SSM).

## Prerequisites

#   An Amazon Virtual Private Cloud (VPC) with 2 private subnets
#   The private subntes should include the tag key kubernetes.io/role/internal-elb , the tag value must be 1
#   An EC2 instance in the private subnet
#   An IAM role with the necessary permissions for EKS and EC2
#   A file called `cluster.yaml` containing the desired configuration for the EKS cluster

## Installing Required Tools

### Eksctl - Latest Version

if [ ! -f /usr/local/bin/eksctl ]
then
  cd /tmp
  curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
  sudo mv /tmp/eksctl /usr/local/bin
fi

### Kubectl 1.23 - This specific version is required 

if [ ! -f /usr/local/bin/kubectl ]
then
  curl -LO https://dl.k8s.io/release/v1.23.16/bin/linux/amd64/kubectl
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  kubectl version --client --output=yaml 
fi

### Helm v3.8.2 - This specific version is required 

if [ ! -f /usr/local/bin/helm ]
then
  curl -L https://git.io/get_helm.sh | bash -s -- --version v3.8.2
#  chmod 700 get_helm.sh
#  ./get_helm.sh
  helm version --short
fi


## Obtain some info first

# accountId
if [ "${accountId}" == "" ]
then
  accountId=$(aws sts get-caller-identity --query "Account" --output text)
else
  accountId=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .accountId -r)
fi
# region
if [ "${region}" == "" ]
then
  region=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r)
fi
# vpcId
if [ "${vpcId}" == "" ]
then
  vpcId=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text)
fi

if [ "${vpcId}" != "" ]
then
  # cidrBlock
  if [ "${cidrBlock}" == "" ]
  then
    cidrBlock=$(aws ec2 describe-vpcs --query 'Vpcs[0].CidrBlock' --output text)
  fi
  # sharedNodeSg
  if [ "${sharedNodeSg}" == "" ]
  then
    sharedNodeSg=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpcId}" "Name=tag:Name,Values=${appPrefix^^}-${environment^^}-VPC-SG-APP" --query "SecurityGroups[*].GroupId" --output text)
  fi
  # subnet1
  if [ "${subnet1}" == "" ]
  then
    subnet1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpcId}" "Name=tag:Name,Values=${appPrefix^^}-${environment^^}-VPC-PRV-APP-01" --query "Subnets[*].SubnetId" --output text)
  fi
  # subnet2
  if [ "${subnet2}" == "" ]
  then
    subnet2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${vpcId}" "Name=tag:Name,Values=${appPrefix^^}-${environment^^}-VPC-PRV-APP-02" --query "Subnets[*].SubnetId" --output text)
  fi
else
  echo "No VPC found, exiting..."
  exit 1
fi

if [ -z "${accountId}" ] || [ -z "${vpcId}" ] || [ -z "${cidrBlock}" ] || [ -z "${sharedNodeSg}" ] || [ -z "${subnet1}" ] || [ -z "${subnet2}" ] || [ -z "${region}" ] || [ -z "${keyARN}" ]
then
  echo "Missing aws configuration parameters"
  exit 1;
fi

## Check if cluster already exists...

existingClusterName=$(aws eks list-clusters --output text | awk '{print $2}')

if [ "${existingClusterName}" != "" ]
then
  echo "EKS Cluster already exists!"
  echo "Comparing to calcuated EKS Cluster Name"
  if [ "${clusterNameLower}" != "${existingClusterName}" ]
  then
    echo "There is an existing EKS cluster and the name differs from the calculated EKS Cluster Name."
    echo "Please verify"
    exit 1
  else
    echo "EKS Cluster Names match! Proceeding..."
  fi
else
  echo "There is no exiting EKS Cluster"
  echo "Creating one with provided info..."

  cat << EOF              > /tmp/cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: "${clusterNameLower}"
  region: "${region}"
  version: "${eksClusterVersion}"

vpc:
  id: "${vpcId}"
  cidr: "${cidrBlock}"
  sharedNodeSecurityGroup: "${sharedNodeSg}"
  subnets:
    private:
      "${region}a":
        # ${clusterNameUpper}-VPC-PRV-APP-01
        id: "${subnet1}"
      "${region}b":
        # ${clusterNameUpper}-VPC-PRV-APP-02
        id: "${subnet2}"
  clusterEndpoints:
    publicAccess: true
    privateAccess: true

secretsEncryption:
  # KMS key used for envelope encryption of Kubernetes secrets
  # ${clusterNameUpper}-KMS-EKS
  keyARN: "${keyARN}"

fargateProfiles:
  - name: "${clusterNameLower}-fargate"
    selectors:
      # All workloads in the "kube-system" Kubernetes namespace will be
      # scheduled onto Fargate:
      - namespace: "${namespace}"
      - namespace: kube-system

      # Namespace requerido para ADOT
      - namespace: fargate-container-insights

iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: "${clusterNameLower}-sa"
        namespace: "${clusterNameLower}-ns"
      attachPolicyARNs:
        - "${CloudWatchWriteAccessPolicyArn}"
        - "${S3ReadWriteAccessPolicyArn}"
        - "${SMKMSReadAccessPolicyArn}"

iamIdentityMappings:

# This is for EC2 (deployer)
  - arn: "${EksIamRoleArn}"
    groups:
      - system:masters
    username: "${appPrefix}-admin"
    noDuplicateARNs: true # prevents shadowing of ARNs

# CodeBuild access
  - arn: "${CbEksIamRoleArn}"
    groups:
      - system:masters
    username: codebuild-eks
    noDuplicateARNs: true # prevents shadowing of ARNs

  - account: "${accountId}" # account must be configured with no other options

cloudWatch:
  clusterLogging:
    # enable specific types of cluster control plane logs
    enableTypes: ["*"]
    # all supported types: "api", "audit", "authenticator", "controllerManager", "scheduler"
    # supported special values: "*" and "all"
    # Sets the number of days to retain the logs for (see [CloudWatch docs](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/API_PutRetentionPolicy.html#API_PutRetentionPolicy_RequestSyntax)).
    # By default, log data is stored in CloudWatch Logs indefinitely.
    logRetentionInDays: 3
EOF

  ## Creating the EKS cluster

  read -p "Create EKS Cluster (Y/N)? " response
  if [ "${response}" == "Y" ]
  then
    eksctl create cluster -f /tmp/cluster.yaml
  fi

fi

### Add 443 ingress rule from the EC2 Bastion Ip or SG to the cluster secondary SG,
### you can do it using the console or using the following commands

# Get the id of the eks sg

sg_id=$(aws eks describe-cluster --name ${clusterNameLower} --query cluster.resourcesVpcConfig.securityGroupIds[0] --region ${region} --output text)

#cidrOrIp=$(ip a show ens5 | grep 'inet ' | awk '{print $2}')

# Change the sg to the above sg id, and update the cidr to the private subnets cidr

aws ec2 authorize-security-group-ingress \
   --group-id ${sg_id}                   \
   --protocol tcp                        \
   --port 443                            \
   --cidr ${cidrBlock}                   \
   --region ${region}

### Get credentials to access the eks cluster
aws eks --region ${region} update-kubeconfig --name ${clusterNameLower} 

### Verify access to eks
kubectl get nodes -A

