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
appPrefix="amx-ppl-cc-des"
accountId=$(aws sts get-caller-identity --query Account --output=text)
vpcId="vpc-0c9d013543a933d4a"
cidrBlock="172.41.0.0/16"
sharedNodeSg="sg-082214b9919e4e655"
subnet1="subnet-07cd59026aeac712c"
subnet2="subnet-0bd033e4eb60eef9d"
region="us-east-1"
clusterName="amx-ppl-cc-des"
namespace="${clusterName}-ns"
keyId="5f54985b-bfb0-47d9-9289-006ffa145b08"

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
#   A file called `cluster.yml` containing the desired configuration for the EKS cluster

## Check if cluster already exists...

eksClusters=$(aws eks list-clusters --output text | awk '{print $2}')
touch tmp/cluster.yaml

#for existingClusterName in ${eksClusters}
#do
#if [ "${eksClusters}" != "" ]
#then
#  echo "EKS Cluster already exists!"
#  echo "Comparing to calcuated EKS Cluster Name"
#  if [ "${clusterName}" != "${existingClusterName}" ]
#  then
#    echo "There is no existing EKS Cluster"
#    echo "Creating one with provided info..."

cat << EOF              > tmp/cluster.yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: "${clusterName}"
  region: "${region}"
  version: "1.24"

vpc:
  id: "${vpcId}"
  cidr: "${cidrBlock}"
  sharedNodeSecurityGroup: "${sharedNodeSg}"
  subnets:
    private:
      "us-east-1a":
        id: "${subnet1}"
      "us-east-1b":
        id: "${subnet2}"
  clusterEndpoints:
    publicAccess: false
    privateAccess: true

secretsEncryption:
  # KMS key used for envelope encryption of Kubernetes secrets
  keyARN: "arn:aws:kms:${region}:${accountId}:key/${keyId}"

 fargateProfiles:
   - name: "${clusterName}-fargate"
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
        name: "${clusterName}-sa"
        namespace: "${clusterName}-ns"
      attachPolicyARNs:
        - "arn:aws:iam::${accountId}:policy/${clusterName}-iam-p-cwtch-write"
        - "arn:aws:iam::${accountId}:policy/${clusterName}-iam-p-s3-read-write"
        - "arn:aws:iam::${accountId}:policy/${clusterName}-iam-p-sm-kms-read"

iamIdentityMappings:
# This is for EC2 (deployer)
  - arn: "arn:aws:iam::${accountId}:role/${clusterName}-iam-rol-eks-deployer"
    groups:
    - system:masters
    username: "${appPrefix}-admin"
    noDuplicateARNs: true # prevents shadowing of ARNs

# CodeBuild access
  - arn: "arn:aws:iam::${accountId}:role/AMX-PPL-CB-EKS-${accountId}-${region}"
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
    npx yaml-lint yamllint tmp/cluster.yaml
    eksctl create cluster -f tmp/cluster.yaml
  fi
# fi
#fi
#done

### Get credentials to access the eks cluster
aws eks --region ${region} update-kubeconfig --name ${clusterName} 

### Verify access to eks
kubectl get nodes -A

### Create a namaspace, the name should match your fargate profile namespace
eksctl create namespace ${namespace}
