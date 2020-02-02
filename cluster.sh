KNMSTATE_VERSION=v0.13.0
KIND_NODE_IMAGE=quay.io/phoracek/kind-node-networkmanager

TMP_CONF=${PWD}/.etc
TMP_VAR=${PWD}/.var
TMP_PATH=${PWD}/.bin

function _tmp_dirs::setup() {
    mkdir -p ${TMP_PATH}
    mkdir -p ${TMP_CONF}
    mkdir -p ${TMP_VAR}
}

function _binaries::_ensure_tmp_binary() {
    name=$1
    url=$2

    if [ ! -f ${TMP_PATH}/${name} ]; then
        curl -Lso ${TMP_PATH}/${name} ${url}
        chmod +x ${TMP_PATH}/${name}
    fi
}

function _binaries::setup() {
    echo 'Installing needed binaries ...'

    echo '   kind'
    _binaries::_ensure_tmp_binary \
        kind \
        https://github.com/kubernetes-sigs/kind/releases/download/v0.7.0/kind-$(uname)-amd64

    echo '   kubectl'
    _binaries::_ensure_tmp_binary \
        kubectl \
        https://storage.googleapis.com/kubernetes-release/release/v1.17.0/bin/linux/amd64/kubectl

    echo '   dnsmasq'
    if ! command -v dnsmasq > /dev/null; then
        yum -y install dnsmasq > /dev/null
    fi

    echo '   Done'
}

function _kind::setup() {
    kind_conf=${TMP_CONF}/kind.yaml

    echo '
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
' > ${kind_conf}
    for _ in $(seq 1 ${WORKER_NODES}); do
        echo '- role: worker' >> ${kind_conf}
    done

    kind create cluster \
         --config ${kind_conf} \
         --wait 5m \
         --image ${KIND_NODE_IMAGE}
}

function _kind::cleanup() {
    kind delete cluster || true
}

function _networks::_random_veth_name() {
    echo "veth$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 11 | head -n 1)"
}

function _networks::_configure_secondary() {
    network=$1
    iface=$2
    gateway=$3
    range=$4

    bridge_netns=kind_${network}
    ip netns add ${bridge_netns}
    ip netns exec ${bridge_netns} ip link add name br1 type bridge

    for node_container_id in $(docker ps | grep kind | cut -d' ' -f1); do
        node_container_pid=$(docker inspect -f '{{.State.Pid}}' ${node_container_id})
        mkdir -p /var/run/netns/
        ln -sfT /proc/${node_container_pid}/ns/net /var/run/netns/${node_container_id}

        veth_noderidge=$(_networks::_random_veth_name)
        veth_node=$(_networks::_random_veth_name)
        ip netns exec ${bridge_netns} ip link add ${veth_noderidge} type veth peer name ${veth_node}
        ip netns exec ${bridge_netns} ip link set ${veth_noderidge} master br1
        ip netns exec ${bridge_netns} ip link set ${veth_noderidge} up
        ip netns exec ${bridge_netns} ip link set ${veth_node} netns ${node_container_id}
        ip netns exec ${node_container_id} ip link set ${veth_node} name ${iface}
        ip netns exec ${node_container_id} ip link set ${iface} up
    done

    ip netns exec ${bridge_netns} ip link set br1 up
    ip netns exec ${bridge_netns} ip address add ${gateway}/24 dev br1

    dnsmasq_conf=${TMP_CONF}/dnsmasq-${network}.conf
    echo "
listen-address=${gateway}
interface=br1
dhcp-range=${range}
dhcp-leasefile=${TMP_VAR}/${network}.leases
" > ${dnsmasq_conf}
    ip netns exec ${bridge_netns} dnsmasq -C ${dnsmasq_conf}
}

function _networks::_cleanup_secondary() {
    network=$1
    ip netns delete kind_${network} || true
    ps aux | grep -e dnsmasq -e ${TMP_VAR} | awk '{print $2}' | xargs kill || true
}

function _networks::setup() {
    for i in $(seq 1 ${SECONDARY_NICS}); do
        _networks::_configure_secondary net${i} eth${i} 192.168.${i}.1 192.168.${i}.2,192.168.${i}.254,12h
    done
}

function _networks::cleanup() {
    echo 'Deleting configured networks ...'
    for i in $(seq 1 20); do
        _networks::_cleanup_secondary net${i} &> /dev/null
    done
}

function cluster::setup() {(
    set -ex

    echo 'Please wait while the Kubernetes cluster is being set up'
    echo 'It should take approximately 2 minutes'  # TODO: test on katacoda with pull of the image

    WORKER_NODES=${WORKER_NODES:-0}
    SECONDARY_NICS=${SECONDARY_NICS:-0}
    NICS_PER_SECONDARY_NETWORK=${NICS_PER_SECONDARY_NETWORK:-1}
    export PATH=$(cluster::path)

    _tmp_dirs::setup
    _binaries::setup
    _kind::setup
    _networks::setup
)}

function cluster::cleanup() {
    _kind::cleanup
    _networks::cleanup
}

function cluster::path() {
    echo ${TMP_PATH}:${PATH}
}
