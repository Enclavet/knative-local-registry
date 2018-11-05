# Local Kubernetes registry for Knative

Knative documents how to use Build with cloud-based registries and authentication,
but you can benefit from a local registry in a couple of ways:

 * Use a disposable registry when experimenting with Knative.
 * Faster & offline Knative builds.
 * No need to set up service accounts.
 * For Source-to-URL workflows hide registry details from users.

There are quite a few registry setups for Kubernetes,
but we haven't found any that works with Knative.
In-container builds and the tag-to-digest resolution of the Serving reconciler
require the same registry URL to be valid for both build and pull.

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
See [development](./DEVELOPMENT.md) for options on how to make it persistent.

## Support

We would love your feedback on this project so don't hesitate to let us know what is wrong and how we could improve it, just file an [issue](https://github.com/triggermesh/knative-local-registry/issues/new)

## Code of Conduct

This work is by no means part of [CNCF](https://www.cncf.io/) but we abide by its [code of conduct](https://github.com/cncf/foundation/blob/master/code-of-conduct.md)
