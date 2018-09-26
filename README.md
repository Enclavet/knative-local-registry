# Local container registry for Knative

With a local Docker registry Knative can be portable between private and public clouds.
It could also provide faster builds, avoiding round trips over public network.
There's also the potential to hide image URLs,
as an implementation detail, for Source-to-URL workflows.

## How does this repo differ from other registry setups?

Most guides on using a local (sometimes called private, but that often means authenticated)
self-hosted registry in Kubernetes recommend using localhost:5000 or 127.0.0.1:5000 as image URL.
That will not work why Knative, or any in-container build technology like Kaniko or Buildah,
because only a sidecar would be reachable at localhost and sidecars don't run when init containers do.

## Requirements for a local registry endpoint

As [ICP](https://medium.com/@zhimin.wen/explore-knative-build-on-on-premise-kubernetes-cluster-ibm-cloud-private-b0e94e59ba9d) pioneered, the essential requirement for a local registry is that "The hostname of the private registry is resolvable".

We currently scope out a requirement that the setup should have no dependencies outside the cluster.
The value of such a requiement can be seen in [NodePort]() vs [LoadBalancer]() Kubernetes services,
where the former is impractical to use (node IP lookup, odd ports etc) but often relied on
because it is consistent across clusters without external meddling.
The reason we scope this out is that we haven't found an appealing solution.
