#!/bin/sh
# Copyright (c), Mysten Labs, Inc.
# SPDX-License-Identifier: Apache-2.0

# - Setup script for nautilus-server that acts as an init script
# - Sets up Python and library paths
# - Configures loopback network and /etc/hosts
# - Waits for secrets.json to be passed from the parent instance.
# - Forwards VSOCK port 3000 to localhost:3000
# - Optionally pulls secrets and sets in environmen variables.
# - Launches nautilus-server

set -e # Exit immediately if a command exits with a non-zero status
echo "run.sh script is running"
export PYTHONPATH=/lib/python3.11:/usr/local/lib/python3.11/lib-dynload:/usr/local/lib/python3.11/site-packages:/lib
export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH

echo "Script completed."
# Assign an IP address to local loopback
busybox ip addr add 127.0.0.1/32 dev lo
busybox ip link set dev lo up

# Add a hosts record, pointing target site calls to local loopback
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.0.64   api.weatherapi.com" >> /etc/hosts






# == ATTENTION: code should be generated here that parses allowed_endpoints.yaml and populate domains here ===

cat /etc/hosts

echo "Waiting for secrets.json"

# Get a json blob with key/value pair for secrets
JSON_RESPONSE=$(socat - VSOCK-LISTEN:7777,reuseaddr)

echo "We have secrets.json"
# Sets all key value pairs as env variables that will be referred by the server
# This is shown as a example below. For production usecases, it's best to set the
# keys explicitly rather than dynamically.
echo "$JSON_RESPONSE" | jq -r 'to_entries[] | "\(.key)=\(.value)"' > /tmp/kvpairs ; while IFS="=" read -r key value; do export "$key"="$value"; done < /tmp/kvpairs ; rm -f /tmp/kvpairs


# Run traffic forwarder in background and start the server
# Forwards traffic from 127.0.0.x -> Port 443 at CID 3 Listening on port 800x
# There is a vsock-proxy that listens for this and forwards to the respective domains

# == ATTENTION: code should be generated here that added all hosts to forward traffic ===
# Traffic-forwarder-block
python3 /traffic_forwarder.py 127.0.0.64 443 3 8101 &





# Listens on Local VSOCK Port 3000 and forwards to localhost 3000
socat VSOCK-LISTEN:3000,reuseaddr,fork TCP:localhost:3000 &

echo "Starting dockerd"

echo "Mounting tmpfs"
mount -t tmpfs -o size=256M tmpfs /run
mount -t tmpfs -o size=4G tmpfs_docker /var/lib/docker

export DOCKER_RAMDISK=true
mount -t proc     proc /proc
mkdir -p /sys/fs/cgroup && mount -t cgroup2 none /sys/fs/cgroup
mkdir -p /run/docker /var/lib/docker
addgroup -S docker

dockerd --host=unix:///run/docker.sock \
        --exec-root=/run/docker \
        --data-root=/var/lib/docker \
        --iptables=false --ip-masq=false --bridge=none &
sleep 5

echo "Loading image"
docker load -i /images/o1js-test.tar.gz
rm -f /images/o1js-test.tar.gz

# reclaim the cache
sync && echo 3 > /proc/sys/vm/drop_caches

echo "Running container"
docker run --rm --pull=never \
           --read-only \
           --tmpfs /tmp:size=64m,exec,nosuid,nodev \
           -e NODE_OPTIONS="--max-old-space-size=512" \
           o1js-test:latest > /tmp/random_field.log 2>&1 &

cat /tmp/random_field.log

echo "Starting nautilus-server"

/nautilus-server