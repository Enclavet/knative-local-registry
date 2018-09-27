# Local container registry for Knative

With a local Docker registry Knative can be portable between private and public clouds.
It could also provide faster builds, avoiding round trips over public network.
There's also the potential to hide image URLs,
as an implementation detail, for Source-to-URL workflows.

## How does this repo differ from other registry setups?

Most guides on using a local (sometimes called private, which sometimes means authenticated)
self-hosted registry in Kubernetes recommend using localhost:5000 or 127.0.0.1:5000 as image URL host.
That will not work with Knative, or any in-container build technology like
[Kaniko](https://github.com/GoogleContainerTools/kaniko) or [Buildah](https://github.com/projectatomic/buildah),
because only a sidecar would be reachable at localhost and sidecars don't run when init containers do.

## Requirements for a local registry endpoint

As [ICP](https://medium.com/@zhimin.wen/explore-knative-build-on-on-premise-kubernetes-cluster-ibm-cloud-private-b0e94e59ba9d) pioneered,
the essential requirement for a local registry is that "The hostname of the private registry is resolvable".
The same hostname and optional :port must work from both nodes' docker daemon and inside the cluster.
Not necessarily resolvable anywhere else.
If you want registry access over public network authentication is also a requirement.

A truly portable registry setup would avoid dependencies outside the cluster.
The value of such a requiement can be seen in `NodePort` vs `LoadBalancer` Kubernetes services,
where the former is impractical to use (involving node IP lookup, odd ports etc) but often relied on
because it is consistent across clusters without external network configuration.

We have yet to find an appealing such zero-assumptions solution,
and while looking we will instead document the options.

## Name resolution

 1. Use Ingress to get a registry URL
    - All Knative clusters have Ingress support.
    - It's safe to assume these days that Ingress manages SSL certificates.
    - Drawback: Image URLs in Knative end user manifests all embed the current hostname.
 2. Use a local DNS that both your nodes and your containers resolve from.
 3. Edit nodes' /etc/hosts to resolve an in-cluster service name, and expose a host port.

Options 2 and 3 are quite equivalent in terms of registry setup,
and we need to consider the docker https convention.

## Supporting TLS

Docker image URLs don't specify protocol.
Instead clients use https for anything that's not 127.0.0.1 or localhost.
SSL requires a TLS certificate that can be validated by all your registry clients.

Kaniko has `--insecure` and `--skip-tls-verify` flags that you could add to your build templates.
The Knative Serving controller, however, exposes no such options.
You can [disable tag-to-digest resolving](https://github.com/knative/serving/blob/v0.1.1/config/config-controller.yaml#L31)
and thus not need to worry about registry access there at all,
but you'll lose support for an important part of the
[Configuration](https://github.com/knative/serving/blob/master/docs/spec/spec.md#configuration) magic.

Ideally we'd like to avoid [Docker daemon config](https://docs.docker.com/registry/insecure/) and custom flags to build steps,
and the potential security holes of skipping TLS validation.

### Accepting a cluster cert during build

With registry TLS certificates generated according to
https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/
you need to do the following in your kaniko build steps:

```
ln -s /var/run/secrets/kubernetes.io/serviceaccount/ca.crt /kaniko/ssl/certs/ca.crt
```

Kaniko will pick it up alongside its default /kaniko/ssl/certs/ca-certificates.crt and accept your registry TLS.
It could be a volumeMount instead of a shell command.
For the Knative step that looks up image digest we might be able to do the same mount.

### Patching the Knative controller

Knative will look up image digests in order to produce revisions.
The controller (soon to be named reconciler) needs access to the image registry to do that.

Pending discussions within the Knative community on how to do this we patch the controller's deployment.

```bash
# Mounts the cluster's CA over the default bundle.
# Under the assumption that controller requires no access to public services.
# This means that image digest lookups are _only_ supported for the local registry.
# And that the controller can't depend on anything else external to the cluster.

DEFAULT_TOKEN_NAME=$(kubectl -n knative-serving get secret -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep default-token-)

kubectl -n knative-serving patch deployment/controller -p $"
spec:
  template:
    spec:
      containers:
      - name: controller
        volumeMounts:
        - name: default-token
          mountPath: /etc/ssl/certs/ca-certificates.crt
          subPath: ca.crt
      volumes:
      - name: default-token
        secret:
          defaultMode: 420
          secretName: $DEFAULT_TOKEN_NAME
"
```

## Use a service account for Build

It's [recommended](https://github.com/knative/docs/blob/master/build/auth.md#basic-authentication-docker)
to set a `serviceAccountName:` in Build resources if your registry requires authentication.

To let manifests support both authenticated and local registries we assume that
a dummy `knative-build` service account exists when authentication is not required.

```bash
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: knative-build
secrets: []
EOF
```

An alternative would be to patch the `default` ServiceAccount in namespaces that build,
as is recommended for [nodes' pull authentication](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#add-imagepullsecrets-to-a-service-account).

## Persistence

This repository is mainly concerned with registry access.
When it works you obviously want to persist images.
There are basically three options.

 1. Run a single replica with a mounted persistent volume.
 2. Mount a ReadWriteMany kind of volume to all replicas.
 3. Use a bucket store.

Edit the registry-config yaml to configure [storage](https://docs.docker.com/registry/configuration/#storage).
Self-hosting is achievable with [Minio](https://minio.io/) and the [s3](https://docs.docker.com/registry/storage-drivers/s3/) driver.

A compelling advantage with S3 or GCS bucket stores is that you can reuse the same bucket across clusters,
getting access to the same images everywhere.
