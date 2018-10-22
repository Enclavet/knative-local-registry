# Automated support for local registry

_Note: With https://github.com/triggermesh/knative-local-registry/pull/4 it looks like we don't need the patching anymore._

## Accepting a cluster-generated cert during build

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

### Automation

 * Watch for the controller deployment in knative-serving.
 * Patch with CA mount according to the above.
 * Watch for build templates.
 * Identify kaniko steps.
 * Patch according to the above.
 * Identify other steps too.
 * Make sure we don't break FROM public registries.

## Use a service account for Build

It's [recommended](https://github.com/knative/docs/blob/master/build/auth.md#basic-authentication-docker)
to set a `serviceAccountName:` in Build resources if your registry requires authentication.

To let manifests support both authenticated and local registries we assume that
a dummy `knative-build` service account exists when authentication is not required.

An alternative would be to patch the `default` ServiceAccount in namespaces that build,
as is recommended for [nodes' pull authentication](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#add-imagepullsecrets-to-a-service-account).

### Automation

 * Watch for build templates.
 * See if they have declare a serviceAccount that we can create a dummy for, by convention.
