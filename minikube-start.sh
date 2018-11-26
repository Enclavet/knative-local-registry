#!/bin/sh
# Copyright 2018 TriggerMesh, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This is only an example based on
# https://github.com/knative/docs/blob/master/install/Knative-with-Minikube.md
# and
# https://github.com/kubernetes/minikube/issues/2162#issuecomment-354392686

set -e

minikube version | grep v0.28 && echo "You might need extra args for <0.29 minikube, see https://github.com/istio/istio.io/pull/2708"

minikube start --memory=8192 --cpus=4 \
  --kubernetes-version=v1.11.4 \
  --vm-driver=hyperkit \
  --network-plugin=cni \
  --container-runtime=containerd \
  --bootstrapper=kubeadm \
  --extra-config=apiserver.enable-admission-plugins="LimitRanger,NamespaceExists,NamespaceLifecycle,ResourceQuota,ServiceAccount,DefaultStorageClass,MutatingAdmissionWebhook"

# TODO add [plugins.cri.registry.mirrors."knative.registry.svc.cluster.local"] to /etc/containerd/config.toml
# pointing to the podIp of the registry pod on the same node (i.e. the one registry pod on minikube)
# and remove the /etc/hosts record

# --insecure-registry 10.0.0.0/24 should not be needed because according to docs "The default service CIDR range will automatically be added"

# We know we need this on minikube. For real clusters check first if docker pull already works.

echo "Starting registry ..."
kubectl create namespace registry
kubectl apply -f templates/

echo "Enable /etc/hosts update ..."
kubectl apply -f sysadmin/

### Would you like to install Knative using github.com/triggermesh/charts?
kubectl cluster-info
# TODO can we run this in k8s instead, to avoid dependence on local Helm?
#helm init
#helm repo add tm https://storage.googleapis.com/triggermesh-charts
#helm repo update
#helm search knative
#helm install tm/knative
#kubectl get pods --all-namespaces -w
