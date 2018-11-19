# Local Kubernetes registry for Knative

A _local_ registry lets you use the same image URLs in all clusters,
in-container (Kaniko builds, Knative tag-to-digest resolver etc.) as well as on nodes (dockerd image pull).
Local registry with temporary storage eliminate a security concern and bandwidth cost of playing around with Knative.
Local registry with persistence to bucket store let multiple clusters share images.
If desired, any one of them can be your production registry.

The question is: How do we chose the hostname for our image URLs?
Running a [Registry](https://hub.docker.com/_/registry/) locally is easy, but:

 * We can't use a real SSL certificate issuer.
 * Docker on k8s nodes typically fails to resolve cluster names.

Knative doesn't (yet?) abstract out the registry URL from Source-to-URL workflows,
so we need the same user-facing FQDNs to work both with Knative and nodes' Docker.

## Set up name resolution

You must chose how to make a registry DNS name resolvable both to pods and to nodes.
See the [development](./DEVELOPMENT.md) readme for background.
There are basically three options:

 * Your nodes do resolve Kubernetes services `*.svc.cluster.local`.
 * An Ingress makes registry reachable through a public FQDN, and you enable authentication.
 * A local DNS or node customization points `knative.registry.svc.cluster.local` to the `clusterIP` of the service.

## Set up the registry

Use `./minikube-start.sh` or apply the [templates](./templates) folder.

See [development](./DEVELOPMENT.md) for more details.

## Persistence

Note that this setup uses transient registry storage.
See [Registry docs](https://docs.docker.com/registry/deploying/#storage-customization) for options on how to make it persistent,
and modify [config](./templates/registry-config.yaml) and/or [volume(s)](./templates/registry.yaml) accordingly.

## Support

We would love your feedback on this project so don't hesitate to let us know what is wrong and how we could improve it, just file an [issue](https://github.com/triggermesh/knative-local-registry/issues/new)

## Code of Conduct

This work is by no means part of [CNCF](https://www.cncf.io/) but we abide by its [code of conduct](https://github.com/cncf/foundation/blob/master/code-of-conduct.md)
