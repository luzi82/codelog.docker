#!/bin/bash

set -e

#####
echo Check python3
python3 --version

echo Check virtualenv
virtualenv --version

echo Check jq
jq --version

#####

REGION=us-west-2

YYYYMMDDHHMMSS=`date +%Y%m%d%H%M%S`
echo YYYYMMDDHHMMSS=${YYYYMMDDHHMMSS}

#####
echo Init local environment

TMP=/tmp/codelog.docker.aws.${YYYYMMDDHHMMSS}
echo TMP=${TMP}
rm -rf venv
rm -rf ${TMP}

mkdir -p ${TMP}

virtualenv -p `which python3` venv
source venv/bin/activate

pip install --upgrade awscli

AWS="aws --region=${REGION}"

echo Check AWS login done
AWS_ACCOUNT_ID=`${AWS} sts get-caller-identity | jq -r .Account`
echo AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}

#####
echo Create AWS cluster
${AWS} ecs create-cluster --cluster-name codelog-docker-cluster > ${TMP}/cluster.json
CLUSTER_ARN=`cat ${TMP}/cluster.json | jq -r ".cluster.clusterArn"`
echo CLUSTER_ARN=${CLUSTER_ARN}

#####
echo Create AWS log group
${AWS} logs create-log-group --log-group-name codelog-docker-log-group

#####
echo Create AWS role
${AWS} iam create-role --role-name codelog-docker-role --assume-role-policy-document file://role_trust.json > ${TMP}/role.json
ROLE_ARN=`cat ${TMP}/role.json | jq -r ".Role.Arn"`
echo ROLE_ARN=${ROLE_ARN}
${AWS} iam put-role-policy --role-name codelog-docker-role --policy-name codelog-docker-policy --policy-document file://policy.json

#####
echo Create AWS ECS task definition
cat task-definition.json | jq '.executionRoleArn = $arn' --arg arn ${ROLE_ARN} > ${TMP}/task-definition.json
${AWS} ecs register-task-definition --cli-input-json file://${TMP}/task-definition.json > ${TMP}/registered-task-definition.json
TASK_DEFINITION_ARN=`cat ${TMP}/registered-task-definition.json | jq -r ".taskDefinition.taskDefinitionArn"`
echo TASK_DEFINITION_ARN=${TASK_DEFINITION_ARN}

#####
echo Create AWS cloudformation stack
${AWS} cloudformation create-stack --stack-name codelog-docker-cf --template-body file://cf.json --parameters file://cf_parameters.json > ${TMP}/cf.json
CF_ID=`cat ${TMP}/cf.json | jq -r ".StackId"`
echo CF_ID=${CF_ID}

echo Wait AWS cloudformation stack create complete
${AWS} cloudformation wait stack-create-complete --stack-name ${CF_ID}
echo DONE

VPC_ID=`${AWS} cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id Vpc | jq -r ".StackResourceDetail.PhysicalResourceId"`
SG_ID=`${AWS} cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id EcsSecurityGroup | jq -r ".StackResourceDetail.PhysicalResourceId"`
SUBNET_0_ID=`${AWS} cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id PublicSubnetAz2 | jq -r ".StackResourceDetail.PhysicalResourceId"`
SUBNET_1_ID=`${AWS} cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id PublicSubnetAz1 | jq -r ".StackResourceDetail.PhysicalResourceId"`
echo VPC_ID=${VPC_ID}
echo SG_ID=${SG_ID}
echo SUBNET_0_ID=${SUBNET_0_ID}
echo SUBNET_1_ID=${SUBNET_1_ID}

#####
echo Create AWS ECS service

cat ecs.service.network.json \
  | jq '.awsvpcConfiguration.subnets[0] = $P' --arg P ${SUBNET_0_ID} \
  | jq '.awsvpcConfiguration.subnets[1] = $P' --arg P ${SUBNET_1_ID} \
  | jq '.awsvpcConfiguration.securityGroups[0] = $P' --arg P ${SG_ID} \
  > ${TMP}/ecs.service.network.json

${AWS} ecs create-service \
  --cluster ${CLUSTER_ARN} \
  --service-name codelog-docker-service \
  --task-definition ${TASK_DEFINITION_ARN} \
  --launch-type FARGATE \
  --desired-count 1 \
  --network-configuration file://${TMP}/ecs.service.network.json \
  > ${TMP}/service.json
SERVICE_ARN=`cat ${TMP}/service.json | jq -r ".service.serviceArn"`
echo SERVICE_ARN=${SERVICE_ARN}

echo Wait AWS ECS service stable
${AWS} ecs wait services-stable --cluster ${CLUSTER_ARN} --services "${SERVICE_ARN}"
echo DONE

#####
echo Find AWS service IP

TASK_ARN=`${AWS} ecs list-tasks --cluster ${CLUSTER_ARN} --service-name "${SERVICE_ARN}" | jq -r ".taskArns[0]"`
echo TASK_ARN=${TASK_ARN}

echo WAIT tasks-running
${AWS} ecs wait tasks-running --cluster ${CLUSTER_ARN} --tasks "${TASK_ARN}"
echo DONE

PUBLIC_IP=`${AWS} ec2 describe-network-interfaces --filters Name=vpc-id,Values=${VPC_ID} | jq -r ".NetworkInterfaces[0].Association.PublicIp"`
echo PUBLIC_IP=${PUBLIC_IP}

#####
echo Test AWS service

curl http://${PUBLIC_IP}

#####
echo Clean up

${AWS} ecs update-service --cluster ${CLUSTER_ARN} --service ${SERVICE_ARN} --desired-count 0 > ${TMP}/service.update.json
#${AWS} ecs wait services-stable --cluster ${CLUSTER_ARN} --service-name "${SERVICE_ARN}"
${AWS} ecs delete-service --cluster ${CLUSTER_ARN} --service ${SERVICE_ARN} > ${TMP}/service.delete.json
${AWS} cloudformation delete-stack --stack-name ${CF_ID}
echo Wait AWS CloudFormation stack delete complete
${AWS} cloudformation wait stack-delete-complete --stack-name ${CF_ID}
echo DONE
${AWS} ecs deregister-task-definition --task-definition ${TASK_DEFINITION_ARN} > ${TMP}/task.deregister.json
${AWS} iam delete-role-policy --role-name codelog-docker-role --policy-name codelog-docker-policy
${AWS} iam delete-role --role-name codelog-docker-role
${AWS} logs delete-log-group --log-group-name codelog-docker-log-group
${AWS} ecs delete-cluster --cluster ${CLUSTER_ARN} > ${TMP}/cluster.delete.json

deactivate
rm -rf venv
rm -rf ${TMP}
