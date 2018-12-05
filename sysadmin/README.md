
## The `registry-etc-hosts-update` daemonset

Apply the [hosts-etc-hosts-update.yaml](./hosts-etc-hosts-update.yaml) manifest to set up a daemonset that attepts to edit `/etc/hosts` on current and future nodes.

The init container adds the `knative.registry.svc.cluster.local` hostname if it's not already present, pointing to the IP of the [knative](../templates/registry-service-knative.yaml) service.

There might be node types for which this edit isn't allowed or doesn't work. To see status use `kubectl -n kube-system logs -l app=registry-etc-hosts-update -c update` which should print out a `getent hosts` command for first time runs and the IP given by  `kubectl -n registry get service knative -o jsonpath='{.spec.clusterIP}'` on subsequent runs.
