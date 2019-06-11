#!/bin/bash

########################
# include the magic
########################
. ../demo-magic/demo-magic.sh

NO_WAIT=false
TYPE_SPEED=40
DEMO_PROMPT="\[\033[01;34m\]\w\[\033[00m\] $ "

# hide the evidence
bash ./teardown_demo_opa.sh
mkdir opa-demo
cd opa-demo

cat >admission-controller.yaml <<EOF
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: opa-viewer
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: Group
  name: system:serviceaccounts:opa
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: opa
  name: configmap-modifier
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: opa
  name: opa-configmap-modifier
roleRef:
  kind: Role
  name: configmap-modifier
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: Group
  name: system:serviceaccounts:opa
  apiGroup: rbac.authorization.k8s.io
---
kind: Service
apiVersion: v1
metadata:
  name: opa
  namespace: opa
spec:
  selector:
    app: opa
  ports:
  - name: https
    protocol: TCP
    port: 443
    targetPort: 443
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    app: opa
  namespace: opa
  name: opa
spec:
  replicas: 1
  selector:
    matchLabels:
      app: opa
  template:
    metadata:
      labels:
        app: opa
      name: opa
    spec:
      containers:
        - name: opa
          image: openpolicyagent/opa:0.10.5
          args:
            - "run"
            - "--server"
            - "--tls-cert-file=/certs/tls.crt"
            - "--tls-private-key-file=/certs/tls.key"
            - "--addr=0.0.0.0:443"
            - "--addr=http://127.0.0.1:8181"
          volumeMounts:
            - readOnly: true
              mountPath: /certs
              name: opa-server
        - name: kube-mgmt
          image: openpolicyagent/kube-mgmt:0.6
          args:
            - "--replicate-cluster=v1/namespaces"
            - "--replicate=extensions/v1beta1/ingresses"
      volumes:
        - name: opa-server
          secret:
            secretName: opa-server
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: opa-default-system-main
  namespace: opa
data:
  main: |
    package system

    import data.kubernetes.admission

    main = {
      "apiVersion": "admission.k8s.io/v1beta1",
      "kind": "AdmissionReview",
      "response": response,
    }

    default response = {"allowed": true}

    response = {
        "allowed": false,
        "status": {
            "reason": reason,
        },
    } {
        reason = concat(", ", admission.deny)
        reason != ""
    }
EOF

clear

# Put your stuff here
echo "██████╗ ███████╗██████╗ ██╗      ██████╗ ██╗   ██╗     ██████╗ ██████╗  █████╗ 
██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗╚██╗ ██╔╝    ██╔═══██╗██╔══██╗██╔══██╗
██║  ██║█████╗  ██████╔╝██║     ██║   ██║ ╚████╔╝     ██║   ██║██████╔╝███████║
██║  ██║██╔══╝  ██╔═══╝ ██║     ██║   ██║  ╚██╔╝      ██║   ██║██╔═══╝ ██╔══██║
██████╔╝███████╗██║     ███████╗╚██████╔╝   ██║       ╚██████╔╝██║     ██║  ██║
╚═════╝ ╚══════╝╚═╝     ╚══════╝ ╚═════╝    ╚═╝        ╚═════╝ ╚═╝     ╚═╝  ╚═╝"
echo ""
echo ""

pe "kubectl get all --all-namespaces"

pe "openssl genrsa -out ca.key 2048"
pe "openssl req -x509 -new -nodes -key ca.key -days 100000 -out ca.crt -subj \"/CN=admission_ca\""

pe "cat >server.conf <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, serverAuth
EOF"

pe "openssl genrsa -out server.key 2048"
pe "openssl req -new -key server.key -out server.csr -subj \"/CN=opa.opa.svc\" -config server.conf"
pe "openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 100000 -extensions v3_req -extfile server.conf"

pe "cat admission-controller.yaml"

pe "cat > webhook-configuration.yaml <<EOF
kind: ValidatingWebhookConfiguration
apiVersion: admissionregistration.k8s.io/v1beta1
metadata:
  name: opa-validating-webhook
webhooks:
  - name: validating-webhook.openpolicyagent.org
    rules:
      - operations: 
        - CREATE
        - UPDATE
        apiGroups: 
        - \"*\"
        apiVersions: 
        - v1
        resources:
        - pods
    clientConfig:
      caBundle: $(cat ca.crt | base64 | tr -d '\n')
      service:
        namespace: opa
        name: opa
EOF"

pe "cat > image_source.rego <<EOF
package kubernetes.admission  
  
import data.kubernetes.namespaces  
  
deny[msg] {  
    input.request.kind.kind = \"Pod\"  
    input.request.operation = \"CREATE\"  
    registry = input.request.object.spec.containers[_].image  
    name = input.request.object.metadata.name  
    namespace = input.request.object.metadata.namespace  
    not reg_matches_any(registry,valid_deployment_registries)  
    msg = sprintf(\"invalid pod, namespace=%q, name=%q, registry=%q\", [namespace,name,registry])  
}  
  
valid_deployment_registries = {registry |  
    whitelist = \"602401143452.dkr.ecr.${AWS_REGION}.amazonaws.com,${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\"  
    registries = split(whitelist, \",\")  
    registry = registries[_]  
}  
  
reg_matches_any(str, patterns) {  
    reg_matches(str, patterns[_])  
}  
  
reg_matches(str, pattern) {  
    contains(str, pattern)  
}
EOF"

pe "cat > nginx.yaml <<EOF
kind: Pod
apiVersion: v1
metadata:
  name: nginx
  labels:
    app: nginx
  namespace: default
spec:
  containers:
  - image: nginx
    name: nginx
EOF"

pe "kubectl create namespace opa"
pe "kubectl config set-context --namespace opa --current"

pe "kubectl create secret tls opa-server --cert=server.crt --key=server.key"

pe "kubectl apply -f admission-controller.yaml"

pe "kubectl apply -f webhook-configuration.yaml"

pe "kubectl create configmap image-source --from-file=image_source.rego"

pe "kubectl get configmap image-source -o jsonpath=\"{.metadata.annotations}\""

pe "kubectl apply -f nginx.yaml"