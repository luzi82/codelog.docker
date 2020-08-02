#!/bin/bash

set -e

#####
# conf

REGION=us-west-2
echo REGION=${REGION}

#####
echo Check local environment

python3 --version
virtualenv --version
jq --version

echo DONE

#####

YYYYMMDDHHMMSS=`date +%Y%m%d%H%M%S`
echo YYYYMMDDHHMMSS=${YYYYMMDDHHMMSS}

#####
echo Init local environment

TMP=/tmp/codelog.docker.aws.${YYYYMMDDHHMMSS}
echo TMP=${TMP}
ENV=${TMP}/_env.sh
echo ENV=${ENV}
rm -rf venv
rm -rf ${TMP}

mkdir -p ${TMP}

echo REGION=${REGION} >> ${ENV}
echo YYYYMMDDHHMMSS=${YYYYMMDDHHMMSS} >> ${ENV}
echo TMP=${TMP} >> ${ENV}
echo ENV=${ENV} >> ${ENV}

virtualenv -p `which python3` venv
source venv/bin/activate

pip install --upgrade awscli

AWS="aws --region=${REGION}"

echo Check AWS login done
AWS_ACCOUNT_ID=`${AWS} sts get-caller-identity | jq -r .Account`
echo AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
echo AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID} >> ${ENV}

#####
echo Create AWS log group
${AWS} logs create-log-group --log-group-name codelog-docker-log-group

#####
echo Create AWS role
${AWS} iam create-role --role-name codelog-docker-role --assume-role-policy-document file://role_trust.json > ${TMP}/role.json
ROLE_ARN=`cat ${TMP}/role.json | jq -r ".Role.Arn"`
echo ROLE_ARN=${ROLE_ARN}
echo ROLE_ARN=${ROLE_ARN} >> ${ENV}
${AWS} iam put-role-policy --role-name codelog-docker-role --policy-name codelog-docker-policy --policy-document file://policy.json

#####
echo Create AWS cluster

CLUSTER_NAME=codelog-cluster-${YYYYMMDDHHMMSS}
echo CLUSTER_NAME=${CLUSTER_NAME}
echo CLUSTER_NAME=${CLUSTER_NAME} >> ${ENV}

${AWS} ecs create-cluster --cluster-name ${CLUSTER_NAME} > ${TMP}/cluster.json
CLUSTER_ARN=`cat ${TMP}/cluster.json | jq -r ".cluster.clusterArn"`
echo CLUSTER_ARN=${CLUSTER_ARN}
echo CLUSTER_ARN=${CLUSTER_ARN} >> ${ENV}

#####
echo Create AWS cloudformation stack

cat cf_parameters.json \
  | jq '.[1].ParameterValue = $v' --arg v ${CLUSTER_NAME} \
  > ${TMP}/cf_parameters.json

${AWS} cloudformation create-stack --stack-name codelog-docker-cf --template-body file://cf.json --parameters file://${TMP}/cf_parameters.json > ${TMP}/cf.json
CF_ID=`cat ${TMP}/cf.json | jq -r ".StackId"`
echo CF_ID=${CF_ID}
echo CF_ID=${CF_ID} >> ${ENV}

echo Wait AWS cloudformation stack create complete
${AWS} cloudformation wait stack-create-complete --stack-name ${CF_ID}
echo DONE

VPC_ID=`${AWS} cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id Vpc | jq -r ".StackResourceDetail.PhysicalResourceId"`
SG_ID=`${AWS} cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id EcsSecurityGroup | jq -r ".StackResourceDetail.PhysicalResourceId"`
SUBNET_0_ID=`${AWS} cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id PublicSubnetAz2 | jq -r ".StackResourceDetail.PhysicalResourceId"`
SUBNET_1_ID=`${AWS} cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id PublicSubnetAz1 | jq -r ".StackResourceDetail.PhysicalResourceId"`
echo VPC_ID=${VPC_ID}
echo VPC_ID=${VPC_ID} >> ${ENV}
echo SG_ID=${SG_ID}
echo SG_ID=${SG_ID} >> ${ENV}
echo SUBNET_0_ID=${SUBNET_0_ID}
echo SUBNET_0_ID=${SUBNET_0_ID} >> ${ENV}
echo SUBNET_1_ID=${SUBNET_1_ID}
echo SUBNET_1_ID=${SUBNET_1_ID} >> ${ENV}

#####
echo Create AWS ECS task definition
TASK_FAMILY=codelog-taskfamily-${YYYYMMDDHHMMSS}
echo TASK_FAMILY=${TASK_FAMILY}
echo TASK_FAMILY=${TASK_FAMILY} >> ${ENV}
cat task-definition.json \
  | jq '.family = $v' --arg v ${TASK_FAMILY} \
  | jq '.executionRoleArn = $arn' --arg arn ${ROLE_ARN} \
  > ${TMP}/task-definition.json
${AWS} ecs register-task-definition --cli-input-json file://${TMP}/task-definition.json > ${TMP}/registered-task-definition.json
TASK_DEFINITION_ARN=`cat ${TMP}/registered-task-definition.json | jq -r ".taskDefinition.taskDefinitionArn"`
echo TASK_DEFINITION_ARN=${TASK_DEFINITION_ARN}
echo TASK_DEFINITION_ARN=${TASK_DEFINITION_ARN} >> ${ENV}

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
echo SERVICE_ARN=${SERVICE_ARN} >> ${ENV}

echo Wait AWS ECS service stable
${AWS} ecs wait services-stable --cluster ${CLUSTER_ARN} --services "${SERVICE_ARN}"
echo DONE

#####
echo Wait AWS ECS service task running

TASK_ARN=`${AWS} ecs list-tasks --cluster ${CLUSTER_ARN} --service-name "${SERVICE_ARN}" | jq -r ".taskArns[0]"`
echo TASK_ARN=${TASK_ARN}
echo TASK_ARN=${TASK_ARN} >> ${ENV}

${AWS} ecs wait tasks-running --cluster ${CLUSTER_ARN} --tasks "${TASK_ARN}"
echo DONE

#####
echo Find AWS ECS service IP

PUBLIC_IP=`${AWS} ec2 describe-network-interfaces --filters Name=vpc-id,Values=${VPC_ID} | jq -r ".NetworkInterfaces[0].Association.PublicIp"`
echo PUBLIC_IP=${PUBLIC_IP}
echo PUBLIC_IP=${PUBLIC_IP} >> ${ENV}

#####
echo Test AWS ECS service

curl http://${PUBLIC_IP}

#####
echo Clean up

${AWS} ecs update-service --cluster ${CLUSTER_ARN} --service ${SERVICE_ARN} --desired-count 0 > ${TMP}/service.update.json
echo Wait AWS ECS service container count = 0
${AWS} ecs wait services-stable --cluster ${CLUSTER_ARN} --service "${SERVICE_ARN}"
echo DONE
${AWS} ecs delete-service --cluster ${CLUSTER_ARN} --service ${SERVICE_ARN} > ${TMP}/service.delete.json
${AWS} ecs deregister-task-definition --task-definition ${TASK_DEFINITION_ARN} > ${TMP}/task.deregister.json
echo Wait AWS ECS service inactive
${AWS} ecs wait services-inactive --cluster ${CLUSTER_ARN} --services "${SERVICE_ARN}"
echo DONE
${AWS} cloudformation delete-stack --stack-name ${CF_ID}
echo Wait AWS CloudFormation stack delete complete
${AWS} cloudformation wait stack-delete-complete --stack-name ${CF_ID}
echo DONE
${AWS} ecs delete-cluster --cluster ${CLUSTER_ARN} > ${TMP}/cluster.delete.json
${AWS} iam delete-role-policy --role-name codelog-docker-role --policy-name codelog-docker-policy
${AWS} iam delete-role --role-name codelog-docker-role
${AWS} logs delete-log-group --log-group-name codelog-docker-log-group

deactivate
rm -rf venv
rm -rf ${TMP}