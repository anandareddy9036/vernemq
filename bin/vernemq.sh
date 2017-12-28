#!/usr/bin/env bash

IP_ADDRESS=$(ip -4 addr show eth0 | grep -oP "(?<=inet).*(?=/)"| sed -e "s/^[[:space:]]*//" | tail -n 1)

# Ensure the Erlang node name is set correctly
if env | grep -q "DOCKER_VERNEMQ_NODENAME"; then
    sed -i.bak -r "s/VerneMQ@.+/VerneMQ@${DOCKER_VERNEMQ_NODENAME}/" /opt/vernemq/etc/vm.args
else
    sed -i.bak -r "s/VerneMQ@.+/VerneMQ@${IP_ADDRESS}/" /opt/vernemq/etc/vm.args
fi

if env | grep -q "DOCKER_VERNEMQ_DISCOVERY_NODE"; then
    echo "-eval \"vmq_server_cmd:node_join('VerneMQ@${DOCKER_VERNEMQ_DISCOVERY_NODE}')\"" >> /opt/vernemq/etc/vm.args
fi

sed -i '/########## Start ##########/,/########## End ##########/d' /opt/vernemq/etc/vernemq.conf

echo "########## Start ##########" >> /opt/vernemq/etc/vernemq.conf

env | grep DOCKER_VERNEMQ | grep -v 'DISCOVERY_NODE\|DOCKER_VERNEMQ_USER' | cut -c 16- | tr '[:upper:]' '[:lower:]' | sed 's/__/./g' >> /opt/vernemq/etc/vernemq.conf

users_are_set=$(env | grep DOCKER_VERNEMQ_USER)
if [ ! -z "$users_are_set" ]
    then
        touch /opt/vernemq/etc/vmq.passwd
fi

for vernemq_user in $(env | grep DOCKER_VERNEMQ_USER);
    do
        username=$(echo $vernemq_user | awk -F '=' '{ print $1 }' | sed 's/DOCKER_VERNEMQ_USER_//g' | tr '[:upper:]' '[:lower:]')
        password=$(echo $vernemq_user | awk -F '=' '{ print $2 }')
        vmq-passwd /opt/vernemq/etc/vmq.passwd $username <<EOF
$password
$password
EOF
    done

echo "erlang.distribution.port_range.minimum = 9100" >> /opt/vernemq/etc/vernemq.conf
echo "erlang.distribution.port_range.maximum = 9109" >> /opt/vernemq/etc/vernemq.conf
echo "listener.tcp.default = ${IP_ADDRESS}:1883" >> /opt/vernemq/etc/vernemq.conf
echo "listener.ssl.default = ${IP_ADDRESS}:8080" >> /opt/vernemq/etc/vernemq.conf
echo "listener.vmq.clustering = ${IP_ADDRESS}:44053" >> /opt/vernemq/etc/vernemq.conf
echo "listener.http.metrics = ${IP_ADDRESS}:8888" >> /opt/vernemq/etc/vernemq.conf

echo "########## End ##########" >> /opt/vernemq/etc/vernemq.conf

# Check configuration file
/opt/vernemq/bin/vernemq config generate 2>&1 > /dev/null | tee /tmp/config.out | grep error

if [ $? -ne 1 ]; then
    echo "configuration error, exit"
    echo "$(cat /tmp/config.out)"
    exit $?
fi

pid=0

# SIGUSR1-handler
siguser1_handler() {
    echo "stopped"
}

# SIGTERM-handler
sigterm_handler() {
    if [ $pid -ne 0 ]; then
        # this will stop the VerneMQ process
        /opt/vernemq/bin/vmq-admin cluster leave node=VerneMQ@$IP_ADDRESS -k > /dev/null
        wait "$pid"
    fi
    exit 143; # 128 + 15 -- SIGTERM
}

# setup handlers
# on callback, kill the last background process, which is `tail -f /dev/null`
# and execute the specified handler
trap 'kill ${!}; siguser1_handler' SIGUSR1
trap 'kill ${!}; sigterm_handler' SIGTERM

/opt/vernemq/bin/vernemq start
pid=$(ps aux | grep '[b]eam.smp' | awk '{print $2}')

while true
do
    tail -f /opt/vernemq/log/console.log & wait ${!}
done