# kind networking

These scripts will setup a multi-node Kubernetes 1.17 cluster with secondary
NICs enabled with DHCP and running NetworkManager.

## Requirements

Make sure you have `dnsmasq` and `docker` available on your host. The other
dependencies should be pulled for you.

## Usage

Helper functions are shipped as a bash library. Before you start using them,
load the sources:

```shell
source cluster.sh
```

Specify the desired configuration of the cluster:

```shell
# number of worker nodes (only master is setup by default)
export WORKER_NODES=1

# Additional isolated L2 networks enabled with a DHCP server
export SECONDARY_NETWORKS=2

# Number of interfaces that will be created in nodes per each secondary network
export NICS_PER_SECONDARY_NETWORK=2
```

Start multi-node kind cluster with kubernetes-nmstate:

> **Caution:** This command will configure networking on the host.

```shell
cluster::setup
```

Delete the cluster:

```shell
cluster::cleanup
```

Get temporary binaries to you `PATH`:

```shell
export PATH=$(cluster::path):${PATH}
```

## Node image

Build kind node image with NetworkManager and push it to public registry:

```shell
docker build -t quay.io/phoracek/kind-node-networkmanager -f Dockerfile .
docker push quay.io/phoracek/kind-node-networkmanager
```
