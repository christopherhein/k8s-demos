#!/bin/bash

kubectl delete -f dynamodb-app.yaml
kubectl delete cm dynamo-table