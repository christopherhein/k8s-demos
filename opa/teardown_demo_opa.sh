#!/bin/bash

kubectl delete namespace opa
kubectl config set-context --namespace default --current

rm -fr opa-demo