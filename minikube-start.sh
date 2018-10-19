#!/bin/sh
# This is only an example based on
# https://github.com/knative/docs/blob/master/install/Knative-with-Minikube.md
# and
# https://github.com/kubernetes/minikube/issues/2162
# https://github.com/kubernetes/minikube/issues/1674

minikube version | grep v0.28 && echo "You might need extra args for <0.29 minikube, see https://github.com/istio/istio.io/pull/2708"

minikube start --memory=8192 --cpus=4 \
  --kubernetes-version=v1.11.3 \
  --vm-driver=hyperkit \
  --bootstrapper=kubeadm \
  --extra-config=apiserver.enable-admission-plugins="LimitRanger,NamespaceExists,NamespaceLifecycle,ResourceQuota,ServiceAccount,DefaultStorageClass,MutatingAdmissionWebhook"
