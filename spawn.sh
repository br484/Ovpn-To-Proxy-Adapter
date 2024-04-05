#!/bin/bash

if [ -f ".env" ]; then
    export $(grep -v '^[[:space:]]*#' .env | xargs)
fi

echo "VPN_LOCATION: $VPN_LOCATION"
echo "VPN_PROVIDER: $VPN_PROVIDER"
echo "STARTING_PORT: $STARTING_PORT"
echo "VPN_USERNAME: $VPN_USERNAME"
echo "VPN_PASSWORD: $VPN_PASSWORD"
echo "CONTAINER_RESTART: $CONTAINER_RESTART"
echo "NETWORK_CIDR: $NETWORK_CIDR"
echo "CONFIG_PATH: $CONFIG_PATH"
echo "MUBENG_PORT: $MUBENG_PORT"
echo "PROXIES_PATH: $PROXIES_PATH"
echo "MUBENG_METHOD: $MUBENG_METHOD"
echo "MUBENG_ROTATE: $MUBENG_ROTATE"


ovpn_list=./ovpn_list
existing_containers=$(docker ps -a --filter "name=haugene-transmission-openvpn" --format "{{.Names}}")

declare -a used_ports

main() {
    vpn_location=$(trim_extension "$VPN_LOCATION")
    if [[ "$vpn_location" = "list" ]]; then
        if [ -e "$ovpn_list" ]; then
            dos2unix "$ovpn_list"
            sed -i '/^$/d' "$ovpn_list"
            sed -i 's/\.ovpn//g' "$ovpn_list"
            echo "" >>"$ovpn_list"
            echo "Found a list with $(wc -l <"$ovpn_list") VPNs."
            cat "$ovpn_list"
            while read line; do
                if ! [[ "$existing_containers" =~ $line ]]; then
                    echo ""
                    echo "Creating container for $line"
                    create_container "$line"
                else
                    echo "Skipping creation of $line. A container with the same name already exists."
                fi
            done <"$ovpn_list"
        else
            echo "No ovpn_list file found. Exiting."
            return 1
        fi
    else
        echo "Creating proxy container for location $vpn_location"
        create_container "$vpn_location"
    fi

    echo "Generating proxy list"
    proxies_list_path="$PROXIES_PATH/proxies.txt"
    proxies_list_path_local="$PROXIES_PATH/proxies_local.txt" # New file with 127.0.0.1

    rm -f "$proxies_list_path"
    rm -f "$proxies_list_path_local"

    for port in "${used_ports[@]}"; do
        echo "http://172.17.0.1:$port" >> "$proxies_list_path"
        echo "http://127.0.0.1:$port" >> "$proxies_list_path_local"
    done

    echo "Proxy list generated for Mubeng at $proxies_list_path"
    echo "Local access proxy list generated at $proxies_list_path_local"

    echo "Configuring the Mubeng rotating proxy container..."

    docker pull ghcr.io/kitabisa/mubeng:latest
    docker run --rm -d -p $MUBENG_PORT:$MUBENG_PORT -v "$PROXIES_PATH":/data ghcr.io/kitabisa/mubeng:latest -a :$MUBENG_PORT -f /data/proxies.txt -m $MUBENG_METHOD -r $MUBENG_ROTATE
    echo "Mubeng proxy container started on port $MUBENG_PORT"

}

create_container() {
    ports_in_use=$(docker ps --format "{{.Ports}}" | cut -d ':' -f2 | cut -d '-' -f 1 | cut -d '/' -f 1)
    while [[ $ports_in_use =~ $STARTING_PORT ]]; do
        echo "Port $STARTING_PORT already in use, trying next port."
        ((STARTING_PORT++))
    done

    vpn_name=$1
    echo "Configuring container for $VPN_PROVIDER"

    docker_run_command="docker run --cap-add=NET_ADMIN -d"

    if [[ -n "$CONFIG_PATH" ]]; then
        docker_run_command+=" -v \"$CONFIG_PATH:/config\""
    fi

    docker_run_command+=" -e \"LOCAL_NETWORK=$NETWORK_CIDR\" \
    -e \"OPENVPN_USERNAME=$VPN_USERNAME\" \
    -e \"OPENVPN_PASSWORD=$VPN_PASSWORD\" \
    -e \"OPENVPN_PROVIDER=$VPN_PROVIDER\" \
    -e \"OPENVPN_CONFIG=$vpn_name\" \
    -e \"WEBPROXY_ENABLED=true\" \
    -e \"WEBPROXY_PORT=8118\" \
    --name=\"haugene-transmission-openvpn-proxy-$vpn_name\" \
    -p \"$STARTING_PORT:8118\" \
    --restart \"$CONTAINER_RESTART\" \
    haugene/transmission-openvpn:latest"

    eval $docker_run_command

    echo "Port mapped to this HTTP proxy: $STARTING_PORT"
    used_ports+=("$STARTING_PORT")
    ((STARTING_PORT++))
}


trim_extension() {
    stripped_name=$(echo "$1" | sed 's/.ovpn$//')
    echo "$stripped_name"
}

main
