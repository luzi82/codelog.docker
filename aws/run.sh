#!/bin/bash

set -e

REGION=us-west-2

YYYYMMDDHHMMSS=`date +%Y%m%d%H%M%S`
TMP=/tmp/codelog.docker.aws.${YYYYMMDDHHMMSS}

echo TMP=${TMP}

rm -rf venv
rm -rf ${TMP}

mkdir -p ${TMP}

virtualenv -p `which python3` venv
source venv/bin/activate

pip install --upgrade awscli

# create cluster
aws ecs create-cluster --cluster-name codelog-docker-cluster --region=${REGION} > ${TMP}/cluster.json
CLUSTER_ARN=`cat ${TMP}/cluster.json | jq -r ".cluster.clusterArn"`
echo CLUSTER_ARN=${CLUSTER_ARN}

# create log group
aws logs create-log-group --log-group-name codelog-docker-log-group --region=${REGION}

# create role
aws iam create-role --role-name codelog-docker-role --assume-role-policy-document file://role_trust.json > ${TMP}/role.json
ROLE_ARN=`cat ${TMP}/role.json | jq -r ".Role.Arn"`
echo ROLE_ARN=${ROLE_ARN}
aws iam put-role-policy --role-name codelog-docker-role --policy-name codelog-docker-policy --policy-document file://policy.json

# create task definition
cat task-definition.json | jq '.executionRoleArn = $arn' --arg arn ${ROLE_ARN} > ${TMP}/task-definition.json
aws ecs register-task-definition --cli-input-json file://${TMP}/task-definition.json --region=${REGION} > ${TMP}/registered-task-definition.json
TASK_DEFINITION_ARN=`cat ${TMP}/registered-task-definition.json | jq -r ".taskDefinition.taskDefinitionArn"`
echo TASK_DEFINITION_ARN=${TASK_DEFINITION_ARN}

# create cloudformation
aws cloudformation create-stack --stack-name codelog-docker-cf --template-body file://cf.json --parameters file://cf_parameters.json --region=${REGION} > ${TMP}/cf.json
CF_ID=`cat ${TMP}/cf.json | jq -r ".StackId"`
echo CF_ID=${CF_ID}

echo WAIT stack-create-complete
aws cloudformation wait stack-create-complete --stack-name ${CF_ID} --region=${REGION}
echo DONE

VPC_ID=`aws cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id Vpc --region=${REGION} | jq -r ".StackResourceDetail.PhysicalResourceId"`
SG_ID=`aws cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id EcsSecurityGroup --region=${REGION} | jq -r ".StackResourceDetail.PhysicalResourceId"`
SUBNET_0_ID=`aws cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id PublicSubnetAz2 --region=${REGION} | jq -r ".StackResourceDetail.PhysicalResourceId"`
SUBNET_1_ID=`aws cloudformation describe-stack-resource --stack-name ${CF_ID} --logical-resource-id PublicSubnetAz1 --region=${REGION} | jq -r ".StackResourceDetail.PhysicalResourceId"`
echo VPC_ID=${VPC_ID}
echo SG_ID=${SG_ID}
echo SUBNET_0_ID=${SUBNET_0_ID}
echo SUBNET_1_ID=${SUBNET_1_ID}

cat ecs.service.network.json \
  | jq '.awsvpcConfiguration.subnets[0] = $P' --arg P ${SUBNET_0_ID} \
  | jq '.awsvpcConfiguration.subnets[1] = $P' --arg P ${SUBNET_1_ID} \
  | jq '.awsvpcConfiguration.securityGroups[0] = $P' --arg P ${SG_ID} \
  > ${TMP}/ecs.service.network.json

aws ecs create-service \
  --cluster ${CLUSTER_ARN} \
  --service-name codelog-docker-service \
  --task-definition ${TASK_DEFINITION_ARN} \
  --launch-type FARGATE \
  --desired-count 1 \
  --network-configuration file://${TMP}/ecs.service.network.json \
  --region=${REGION} \
  > ${TMP}/service.json
SERVICE_ARN=`cat ${TMP}/service.json | jq -r ".service.serviceArn"`
echo SERVICE_ARN=${SERVICE_ARN}

echo WAIT services-stable
aws ecs wait services-stable --cluster ${CLUSTER_ARN} --services "${SERVICE_ARN}" --region=${REGION}
echo DONE

TASK_ARN=`aws ecs list-tasks --cluster ${CLUSTER_ARN} --service-name "${SERVICE_ARN}" --region=${REGION} | jq -r ".taskArns[0]"`
echo TASK_ARN=${TASK_ARN}

echo WAIT tasks-running
aws ecs wait tasks-running --cluster ${CLUSTER_ARN} --tasks "${TASK_ARN}" --region=${REGION}
echo DONE

PUBLIC_IP=`aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=${VPC_ID} --region=${REGION} | jq -r ".NetworkInterfaces[0].Association.PublicIp"`
echo PUBLIC_IP=${PUBLIC_IP}

# test service

curl http://${PUBLIC_IP}

# clean up

aws ecs update-service --cluster ${CLUSTER_ARN} --service ${SERVICE_ARN} --desired-count 0 --region=${REGION} > ${TMP}/service.update.json
#aws ecs wait services-stable --cluster ${CLUSTER_ARN} --service-name "${SERVICE_ARN}" --region=${REGION}
aws ecs delete-service --cluster ${CLUSTER_ARN} --service ${SERVICE_ARN} --region=${REGION} > ${TMP}/service.delete.json
aws cloudformation delete-stack --stack-name ${CF_ID} --region=${REGION}
echo WAIT stack-delete-complete
aws cloudformation wait stack-delete-complete --stack-name ${CF_ID} --region=${REGION}
echo DONE
aws ecs deregister-task-definition --task-definition ${TASK_DEFINITION_ARN} --region=${REGION} > ${TMP}/task.deregister.json
aws iam delete-role-policy --role-name codelog-docker-role --policy-name codelog-docker-policy --region=${REGION}
aws iam delete-role --role-name codelog-docker-role --region=${REGION}
aws logs delete-log-group --log-group-name codelog-docker-log-group --region=${REGION}
aws ecs delete-cluster --cluster ${CLUSTER_ARN} --region=${REGION} > ${TMP}/cluster.delete.json

deactivate

rm -rf venv

rm -rf ${TMP}
