# Local Kubernetes registry for Knative

A _local_ registry lets you use the same image URLs in all clusters,
in-container (Kaniko builds, Knative tag-to-digest resolver etc.) as well as on nodes (dockerd image pull).
Local registry with temporary storage eliminates a security concern and bandwidth cost of playing around with Knative.
Local registry with S3/GCS persistence lets multiple clusters share images.
If desired, any one of them can be your production registry,
exposed with your choice of security to outside the cluster.

The question is: How do we chose the hostname for our image URLs?
Running [registry](https://hub.docker.com/_/registry/) in Kubernetes is trivial, but:

 * We can't use a real SSL certificate issuer.
 * Docker on k8s nodes typically fails to resolve cluster DNS names.

Knative doesn't (yet?) abstract out the registry host from Source-to-URL workflows,
so we need the same user-facing FQDNs to work both with Knative and nodes' Docker.

In this example setup we've chosen `knative.registry.svc.cluster.local` as _the_ registry host.
Using `.local` we by docker conventions avoid SSL,
and we communicate the scope of the configuration.

## Set up name resolution

You must chose how to make a registry DNS name resolvable to nodes.
There are basically three options:

 * Docker daemons somehow resolve Kubernetes services `*.svc.cluster.local`.
 * You add the chosen registry FQDN to `/etc/hosts` on all nodes, including those provisioned in future.
 * A local DNS points `knative.registry.svc.cluster.local` to the `clusterIP` of the service.

## Set up the registry

Use `./minikube-start.sh` or apply the [templates](./templates) folder.

If docker pull fails, which is likely (you can use our [test](./test) jobs to check),
you need to work on the name resolution.
An example of how is in the [sysadmin](./sysadmin) folder.

## Persistence

Note that this setup uses transient registry storage.
See [Registry docs](https://docs.docker.com/registry/deploying/#storage-customization) for options on how to make it persistent,
and modify [config](./templates/registry-config.yaml) and/or [volume(s)](./templates/registry.yaml) accordingly.

It's worth pointing out that S3/GCS persistence is particularily useful for local registry,
as any other cluster or registry setup that can access the same bucket is automatically a mirror.
Furthermore it makes horizontal scaling as easy as `kubectl scale` on the registry replicaset.

## Support

We would love your feedback on this project so don't hesitate to let us know what is wrong and how we could improve it, just file an [issue](https://github.com/triggermesh/knative-local-registry/issues/new)

## Code of Conduct

This work is by no means part of [CNCF](https://www.cncf.io/) but we abide by its [code of conduct](https://github.com/cncf/foundation/blob/master/code-of-conduct.md)
