# Local container registry for Knative

TL;DR:

 * It's convenient to have a local Docker registry.
 * Knative won't work with typical such Kubernetes addons.
 * This repository installs a registry accessible at `knative.registry.svc.cluster.local`.
 * Prefer TLS validation over `--insecure-registry`, for security.

## Why local

With a local Docker registry, Knative can be portable between private and public clouds.

You might also get faster builds, avoiding round trips over public network.
Furthermore, provided Knative evolves in that direction,
image URLs could be hidden from Source-to-URL workflows as an implementation detail.

A local setup may also speed up testing, for example [e2e](https://github.com/kubernetes/community/blob/master/contributors/devel/e2e-tests.md#local-clusters) `go test`,
when developing services on top of Knative.

## How does this repo differ from other registry setups?

Most guides on using a local (sometimes called private, which sometimes means authenticated)
self-hosted registry in Kubernetes recommend using localhost:5000 or 127.0.0.1:5000 as image URL host.
That will not work with Knative, or any in-container build technology like
[Kaniko](https://github.com/GoogleContainerTools/kaniko) or [Buildah](https://github.com/projectatomic/buildah),
because only a sidecar would be reachable at localhost and sidecars don't run when init containers do.

Alternatively a cluster service is used with [insecure registry](https://github.com/kubernetes/minikube/blob/v0.30.0/docs/insecure_registry.md) config,
but in this setup we propose supporting TLS using the cluster CA instead.
The [default service account](https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/#trusting-tls-in-a-cluster) grants pods access to that CA.

## Requirements for a local registry endpoint

As [ICP](https://medium.com/@zhimin.wen/explore-knative-build-on-on-premise-kubernetes-cluster-ibm-cloud-private-b0e94e59ba9d) showed,
the essential requirement for a local registry is that "The hostname of the private registry is resolvable".
The same hostname and optional :port must work from both nodes' docker daemon and inside the cluster,
but not necessarily from anywhere else.
If you do want registry access over public network, [authentication](https://docs.docker.com/registry/deploying/#restricting-access) is a must.

A truly portable registry setup would avoid dependencies outside the cluster.
The value of such a requirement can be seen in `NodePort` vs `LoadBalancer` Kubernetes services,
where the former is impractical to use (involving node IP lookup, odd ports etc) but often relied on
because it is consistent across clusters without external network configuration.

We have yet to find an appealing such zero-assumptions solution,
and while looking we will instead document the options.

## Name resolution

Methods to meet the above requirement include, but are not limited to:

 1. Use Ingress to get a registry URL
    - All Knative clusters have Ingress support.
    - It's safe to assume these days that Ingress manages SSL certificates.
    - Drawback: Image URLs in Knative end user manifests all embed the current hostname.
    - Warning: Your registry must do authentication before you create an Ingress resource for it.
 2. Use a local DNS that both your nodes and your containers resolve from.
 3. Edit nodes' /etc/hosts to resolve an in-cluster service name, and expose a host port.

Options 2 and 3 are quite equivalent in terms of registry setup,
and we need to consider the docker https convention.

## Supporting TLS

Docker image URLs don't specify protocol.
Instead clients use https for anything that's not 127.0.0.1 or localhost.
SSL requires a TLS certificate that can be validated by all your registry clients.

Kaniko has `--insecure` and `--skip-tls-verify` flags that you could add to your build templates.
Note however that they [recommend against](https://github.com/GoogleContainerTools/kaniko#--skip-tls-verify)
using it for production.
Lacking CIDR range support it will affect public registry access too
(such as `FROM docker.io/...`) which opens up a security vulnerability.

The Knative Serving controller, however, exposes no insecure options.
You can [disable tag-to-digest resolving](https://github.com/knative/serving/blob/v0.1.1/config/config-controller.yaml#L31)
and thus not need to worry about registry access there at all,
but you'll lose support for an important part of the automatic
[Revision](https://github.com/knative/docs/tree/master/serving#serving-resources) support.

Ideally we'd like to avoid [Docker daemon config](https://docs.docker.com/registry/insecure/) and custom flags to build steps,
and the potential security holes of skipping TLS validation.

With the current Knative version we rely on a couple of [hacks to trust cluster CA](./knative-registry-operator).

### A proposed portable setup

Observations with Minikube:
 * https://github.com/kubernetes/minikube/blob/v0.30.0/docs/insecure_registry.md#enabling-docker-insecure-registry
 * ... but CLI help says ["The default service CIDR range will automatically be added."](https://github.com/kubernetes/minikube/blob/v0.30.0/cmd/minikube/cmd/start.go#L398)
 * ... and minikube has the cluster CA at `/var/lib/minikube/certs/ca.crt` so it could probably be trusted by docker.

Observations with GKE:
 * [Alias IPs](https://cloud.google.com/vpc/docs/alias-ip) sounds like something that implies resolvable names.

Observations with X:
 * TODO

## The `knative-local-registry` name

Note: _This name has been deprecated because it was impractical to add the alias to namespaces._

With a proxy DaemonSet that exposes registry as `hostPort` on each node,
docker can access images using localhost.
The same name can be used in-cluster if we rely on an [ExternalName](https://kubernetes.io/docs/concepts/services-networking/service/#externalname) service,
also providing a level of abstraction that can be used to chose for example
unauthenticated or authenticated access.
We chose a name without a TLD so it can't be resolvable on public Internet.

Apply [./templates/registry-alias-in-each-namespace.yaml](./templates/registry-alias-in-each-namespace.yaml) in all namespaces where you want this resolvable.

With CoreDNS (Kubernetes 1.11) make sure you run a version that has https://github.com/coredns/coredns/pull/2040:

```
kubectl -n kube-system set image deploy/coredns coredns=k8s.gcr.io/coredns:1.2.2
```

... but this appears to be fixed already in Minikube 0.30.

### On minikube

Run `minikube ssh` followed by `echo "127.0.0.1 knative-local-registry" | sudo tee -a /etc/hosts`.

You might also want `echo '127.0.0.1 unauthenticated.registry.svc.cluster.local' | sudo tee -a /etc/hosts`.
See https://github.com/triggermesh/go-containerregistry/tree/registry-allow-port for why.

## Support

We would love your feedback on this project so don't hesitate to let us know what is wrong and how we could improve it, just file an [issue](https://github.com/triggermesh/knative-local-registry/issues/new)

## Code of Conduct

This work is by no means part of [CNCF](https://www.cncf.io/) but we abide by its [code of conduct](https://github.com/cncf/foundation/blob/master/code-of-conduct.md)
