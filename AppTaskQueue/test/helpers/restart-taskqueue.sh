#!/usr/bin/env bash
#
# Upgrades appscale-taskqueue package if sources are provided.
# Starts TaskQueue servers on specified ports.

set -e
set -u

usage() {
    echo "Usage: ${0} --ports <PORTS> --db-ip <IP> --zk-ip <IP>  --lb-ip <IP> [--source-dir <TQ_DIR>]"
    echo
    echo "Options:"
    echo "   --ports <PORT,PORT>    Comma-separated list of ports to start TQ on"
    echo "   --db-ip <IP>           IP of the database machine (cassandra and datastore)"
    echo "   --zk-ip <IP>           IP of the zookeeper machine"
    echo "   --lb-ip <IP>           IP of the AppScale loadbalancer machine"
    echo "   --source-dir <TQ_DIR>  TaskQueue sources path to use for upgrade"
    exit 1
}

PORTS=
DB_IP=
ZK_IP=
LB_IP=
TQ_SOURCE_DIR=

# Let's get the command line arguments.
while [ $# -gt 0 ]; do
    if [ "${1}" = "--ports" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        PORTS="${1}"
        shift
        continue
    fi
    if [ "${1}" = "--db-ip" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        DB_IP="${1}"
        shift
        continue
    fi
    if [ "${1}" = "--zk-ip" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        ZK_IP="${1}"
        shift
        continue
    fi
    if [ "${1}" = "--lb-ip" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        LB_IP="${1}"
        shift
        continue
    fi
    if [ "${1}" = "--source-dir" ]; then
        shift
        if [ -z "${1}" ]; then
            usage
        fi
        TQ_SOURCE_DIR="${1}"
        shift
        continue
    fi
    usage
done

log() {
    LEVEL=${2:-INFO}
    echo "$(date +'%a %b %d %T %Y'): $LEVEL $1"
}

if [ -z ${PORTS} ] || [ -z ${DB_IP} ] || [ -z ${ZK_IP} ] || [ -z ${LB_IP} ]; then
    usage
fi

if [ ! -z ${TQ_SOURCE_DIR} ]; then
    log "Installing TaskQueue from specified sources"
    pip install --upgrade "${TQ_SOURCE_DIR}"
fi

log "Filling /etc/appscale/* files with addresses of required services"
echo ${DB_IP} > /etc/appscale/master
echo ${DB_IP} > /etc/appscale/slaves
echo "{\"locations\":[\"${ZK_IP}\"]}" > /etc/appscale/zookeeper_locations.json
echo ${LB_IP} > /etc/appscale/load_balancer_ips


RUNNING_SERVER=$(ps -ax | grep "[a]ppscale-taskqueue" || echo "")
if [ ! -z "${RUNNING_SERVER}" ]; then
    log "Killing currently running TaskQueue processes:"
    log "${RUNNING_SERVER}"
    echo "${RUNNING_SERVER}" | awk '{ print $1 }' | xargs kill
fi

PORTS=$(echo "${PORTS}" | sed "s/,/ /g")
log "Starting taskqueue servers on ports: ${PORTS}"
for port in ${PORTS}
do
  nohup appscale-taskqueue -p "${port}" --verbose > "/var/log/appscale/taskqueue-${port}.log" 2>&1 &
done

log "Ensuring servers are running"
for port in ${PORTS}
do
  while ! curl localhost:${port}; do sleep 1; done
done
