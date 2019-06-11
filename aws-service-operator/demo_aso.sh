#!/bin/bash

########################
# include the magic
########################
. ../demo-magic/demo-magic.sh

NO_WAIT=false
TYPE_SPEED=40
DEMO_PROMPT="\[\033[01;34m\]\w\[\033[00m\] $ "

# hide the evidence
bash ./teardown_demo_aso.sh
kubectl delete namespace opa
kubectl config set-context --namespace default --current
clear

p "kubectl apply -f aws-service-operator.yaml"
echo "namespace/aws-service-operator created"
echo "customresourcedefinition.apiextensions.k8s.io/cloudformationtemplates.service-operator.aws created"
echo "customresourcedefinition.apiextensions.k8s.io/dynamodbs.service-operator.aws created"
echo "customresourcedefinition.apiextensions.k8s.io/ecrrepositories.service-operator.aws created"
echo "customresourcedefinition.apiextensions.k8s.io/elasticaches.service-operator.aws created"
echo "customresourcedefinition.apiextensions.k8s.io/s3buckets.service-operator.aws created"
echo "customresourcedefinition.apiextensions.k8s.io/snssubscriptions.service-operator.aws created"
echo "customresourcedefinition.apiextensions.k8s.io/snstopics.service-operator.aws created"
echo "customresourcedefinition.apiextensions.k8s.io/sqsqueues.service-operator.aws created"
echo "clusterrole.rbac.authorization.k8s.io/aws-service-operator created"
echo "serviceaccount/aws-service-operator created"
echo "clusterrolebinding.rbac.authorization.k8s.io/aws-service-operator created"
echo "deployment.apps/aws-service-operator created"

pe "kubectl get customresourcedefinitions"

pe "cat dynamodb-app.yaml"

pe "kubectl apply -f dynamodb-app.yaml"

pe "kubectl get po"

until \
    echo "kubectl get dynamodb dynamo-table -o jsonpath=\"{.status.resourceStatus}\""
    ST=$(kubectl get dynamodb dynamo-table -o jsonpath="{.status.resourceStatus}"); \
        echo $ST; echo $ST | grep "CREATE_COMPLETE"
    do sleep 5
done

pe "kubectl get service -o wide"
