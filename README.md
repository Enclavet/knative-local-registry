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
The Knative Serving controller, however, exposes no such options.
You can [disable tag-to-digest resolving](https://github.com/knative/serving/blob/v0.1.1/config/config-controller.yaml#L31)
and thus not need to worry about registry access there at all,
but you'll lose support for an important part of the automatic
[Revision](https://github.com/knative/docs/tree/master/serving#serving-resources) support.

Ideally we'd like to avoid [Docker daemon config](https://docs.docker.com/registry/insecure/) and custom flags to build steps,
and the potential security holes of skipping TLS validation.

### Accepting a cluster-generated cert during build

With registry TLS certificates generated according to
https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster/
you need to make sure the cluster CA is trusted where required in Knative.

Serving's "tag to digest" feature will look up image digests in order to produce revisions.
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
kubectl -n knative-serving get pods -w
```

Similarly we can patch any Kaniko build steps that push to the registry,
or pulls any of your local images as [FROM](https://docs.docker.com/engine/reference/builder/#from).
For example, assuming it's the second build step that pushes,
as in the [nodejs-runtime](https://github.com/triggermesh/nodejs-runtime) template:

```bash
NAMESPACE=default
DEFAULT_TOKEN_NAME=$(kubectl -n $NAMESPACE get secret -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep default-token-)
BUILD_TEMPLATE_NAME=runtime-nodejs
kubectl -n $NAMESPACE patch buildtemplate.build.knative.dev/$BUILD_TEMPLATE_NAME --type=json -p $"
  [{
    \"op\": \"add\",
    \"path\": \"/spec/volumes\",
    \"value\": [
      {
        \"name\": \"default-token\",
        \"secret\": {
          \"defaultMode\": 420,
          \"secretName\": \"$DEFAULT_TOKEN_NAME\"
        }
      }
    ]
  }]"
STEP_INDEX=1
kubectl -n $NAMESPACE patch buildtemplate.build.knative.dev/$BUILD_TEMPLATE_NAME --type=json -p $"
  [{
    \"op\": \"add\" ,
    \"path\": \"/spec/steps/$STEP_INDEX/volumeMounts\" ,
    \"value\": [
      {
        \"mountPath\": \"/kaniko/ssl/certs/ca.crt\",
        \"name\": \"default-token\",
        \"subPath\": \"ca.crt\"
      }
    ]
  }]"
```

If you'd rather modify the source (but note that the token name is per namespace):

```diff
      image: gcr.io/kaniko-project/executor
      args:
      - --destination=${_IMAGE}:${TAG}
+     volumeMounts:
+     - name: default-token
+       mountPath: /kaniko/ssl/certs/ca.crt
+       subPath: ca.crt
+   volumes:
+   - name: default-token
+     secret:
+       defaultMode: 420
+       secretName: default-token-XXXXX
```

A symlink `ln -s /var/run/secrets/kubernetes.io/serviceaccount/ca.crt /kaniko/ssl/certs/ca.crt`
works too, so alternatively you could use an image built from `gcr.io/kaniko-project/executor`.

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

## The `knative-local-registry` name

We chose a name without a TLD so it can't be resolvable on public Internet.

Apply [./templates/registry-alias-in-each-namespace.yaml](./templates/registry-alias-in-each-namespace.yaml) in all namespaces where you want this resolvable.

With CoreDNS (Kubernetes 1.11) make sure you run a version that has https://github.com/coredns/coredns/pull/2040:

```
kubectl -n kube-system set image deploy/coredns coredns=k8s.gcr.io/coredns:1.2.2
```

... but this appears to be fixed already in Minikube 0.30.

### On minikube

Run `minikube ssh` followed by `echo "127.0.0.1 knative-local-registry" | sudo tee -a /etc/hosts`.
