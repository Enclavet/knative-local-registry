#!/bin/sh
# This is only an example based on
# https://github.com/knative/docs/blob/master/install/Knative-with-Minikube.md
# and
# https://github.com/kubernetes/minikube/issues/2162#issuecomment-354392686

set -e

minikube version | grep v0.28 && echo "You might need extra args for <0.29 minikube, see https://github.com/istio/istio.io/pull/2708"

minikube start --memory=8192 --cpus=4 \
  --kubernetes-version=v1.11.3 \
  --vm-driver=hyperkit \
  --bootstrapper=kubeadm \
  --extra-config=apiserver.enable-admission-plugins="LimitRanger,NamespaceExists,NamespaceLifecycle,ResourceQuota,ServiceAccount,DefaultStorageClass,MutatingAdmissionWebhook"

# --insecure-registry 10.0.0.0/24 should not be needed because according to docs "The default service CIDR range will automatically be added"

minikube addons list | grep -E "coredns|kube-dns"

echo "Updating minikube DNS resolution, see github.com/kubernetes/minikube/issues/2162"
kubectl get svc kube-dns -n kube-system
DNS_IP=$(kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}')
echo "kube-dns IP is $DNS_IP"

echo "Updating resolv.conf ..."
# Is there a way to rsh with minikube ssh?
ssh -i $(minikube ssh-key) -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no docker@$(minikube ip) \
  "sudo sed -i 's/^nameserver/nameserver $DNS_IP\nnameserver/' /etc/resolv.conf"
