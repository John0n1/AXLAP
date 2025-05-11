#!/bin/bash

# AXLAP - Autonomous XKeyscore-Like Analysis Platform
# Installation Script

set -o pipefail # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
AXLAP_BASE_DIR="${AXLAP_INSTALL_DIR:-/opt/axlap}" # Allow overriding base directory
AXLAP_REPO_URL="https://github.com/John0n1/axlap.git"
AXLAP_BRANCH="main"

CAPTURE_INTERFACE="${AXLAP_CAPTURE_INTERFACE:-eth0}"

DEFAULT_LOCAL_NETS="192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
# Try to detect Docker's default bridge network or common virtual machine networks.
# This is a best-effort and might need manual adjustment.
DETECTED_DOCKER_NETS=$(ip -o addr show docker0 2>/dev/null | awk '{print $4}' | head -n1)
HOME_NETS_ARRAY=()
IFS=',' read -ra DEFAULT_NETS_ARRAY <<< "${DEFAULT_LOCAL_NETS}"
for net in "${DEFAULT_NETS_ARRAY[@]}"; do HOME_NETS_ARRAY+=("$net"); done
if [ -n "$DETECTED_DOCKER_NETS" ]; then HOME_NETS_ARRAY+=("$DETECTED_DOCKER_NETS"); fi
# Add common VirtualBox/VMware NAT networks
HOME_NETS_ARRAY+=("192.168.56.0/24") # VirtualBox Host-Only
HOME_NETS_ARRAY+=("172.28.0.0/16")   # Default AXLAP Docker Compose network (from yml)

# Join unique networks
UNIQUE_HOME_NETS=$(echo "${HOME_NETS_ARRAY[@]}" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
HOME_NETS="${AXLAP_HOME_NETS:-${UNIQUE_HOME_NETS}}"

OPENCTI_ADMIN_EMAIL="${OPENCTI_ADMIN_EMAIL:-admin@axlap.local}"
OPENCTI_ADMIN_PASSWORD="${OPENCTI_ADMIN_PASSWORD:-ChangeMeAXLAP!$(openssl rand -hex 12)}"
OPENCTI_ADMIN_TOKEN="${OPENCTI_ADMIN_TOKEN:-$(openssl rand -hex 32)}"

MISP_URL="${MISP_URL:-}" # Leave empty if not used
MISP_KEY="${MISP_KEY:-}"  # Leave empty if not used
CONNECTOR_MISP_ID="${CONNECTOR_MISP_ID:-$(uuidgen)}"

CONNECTOR_EXPORT_FILE_STIX_ID="${CONNECTOR_EXPORT_FILE_STIX_ID:-$(uuidgen)}"
CONNECTOR_IMPORT_FILE_STIX_ID="${CONNECTOR_IMPORT_FILE_STIX_ID:-$(uuidgen)}"

ARKIME_PASSWORD_SECRET="${ARKIME_PASSWORD_SECRET:-AXLAP_Secret_$(openssl rand -hex 24)}"

MINIO_ROOT_USER="${MINIO_ROOT_USER:-axlap_minio_admin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-ChangeMeAXLAP!minio_$(openssl rand -hex 12)}"

LOG_DIR="${AXLAP_BASE_DIR}/logs"
LOG_FILE="${LOG_DIR}/install.log"
ENV_FILE="${AXLAP_BASE_DIR}/.env"
DOCKER_COMPOSE_FILE="${AXLAP_BASE_DIR}/docker-compose.yml"

# --- Helper Functions ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR: This script must be run as root or with sudo."
        exit 1
    fi
}

check_os() {
    if ! grep -qi "ubuntu" /etc/os-release; then
        log "WARNING: This script is primarily tested on Ubuntu. Your OS might require manual adjustments."
    fi
    source /etc/os-release
    local major_version_id
    major_version_id=$(echo "${VERSION_ID:-0}" | cut -d. -f1) # Default to 0 if VERSION_ID is not set
    
    # Ensure major_version_id is a number before comparison
    if [[ "${major_version_id}" =~ ^[0-9]+$ ]] && [ "${major_version_id}" -lt "20" ]; then
        log "WARNING: Ubuntu 20.04 or newer is strongly recommended. Your version: ${VERSION_ID:-N/A}"
    elif ! [[ "${major_version_id}" =~ ^[0-9]+$ ]]; then
        log "WARNING: Could not determine Ubuntu major version. Your VERSION_ID: ${VERSION_ID:-N/A}"
    fi
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log "ERROR: Command '$1' not found. Please install it and try again."
        exit 1
    fi
}

create_directories() {
    log "Creating AXLAP directories under ${AXLAP_BASE_DIR}..."
    mkdir -p "${LOG_DIR}"
    mkdir -p "${AXLAP_BASE_DIR}/data/elasticsearch_data"
    mkdir -p "${AXLAP_BASE_DIR}/data/arkime_pcap"
    # Arkime data is within the main Elasticsearch instance in this setup.
    mkdir -p "${AXLAP_BASE_DIR}/data/opencti_data/s3"
    mkdir -p "${AXLAP_BASE_DIR}/data/opencti_data/redis"
    mkdir -p "${AXLAP_BASE_DIR}/data/opencti_data/es_octi"
    mkdir -p "${AXLAP_BASE_DIR}/data/zeek_logs_raw"
    mkdir -p "${AXLAP_BASE_DIR}/data/suricata_logs"
    mkdir -p "${AXLAP_BASE_DIR}/data/ml_models_data" # For ML models and scalers
    mkdir -p "${AXLAP_BASE_DIR}/rules/suricata_custom" # For custom Suricata rules
    mkdir -p "${AXLAP_BASE_DIR}/config/zeek/site"
    mkdir -p "${AXLAP_BASE_DIR}/config/zeek/intel" # For Zeek threat intel files
    mkdir -p "${AXLAP_BASE_DIR}/config/zeek/plugin_configs"
    mkdir -p "${AXLAP_BASE_DIR}/scripts" # Ensure scripts dir exists for axlap_common_env.sh
    mkdir -p "${AXLAP_BASE_DIR}/venv"   # For Python virtual environment

    # Set permissions for Elasticsearch data directory if it's newly created
    # Elasticsearch container runs as user elasticsearch (uid 1000)
    # This is often handled by Docker volume mounts, but explicit chown can prevent issues.
    if [ -d "${AXLAP_BASE_DIR}/data/elasticsearch_data" ]; then
        log "Setting permissions for ${AXLAP_BASE_DIR}/data/elasticsearch_data..."
        chown -R 1000:1000 "${AXLAP_BASE_DIR}/data/elasticsearch_data" || log "Warning: Could not chown elasticsearch_data. Check permissions."
        chmod -R g+w "${AXLAP_BASE_DIR}/data/elasticsearch_data" || log "Warning: Could not chmod elasticsearch_data."
    fi
    if [ -d "${AXLAP_BASE_DIR}/data/opencti_data/es_octi" ]; then
        log "Setting permissions for ${AXLAP_BASE_DIR}/data/opencti_data/es_octi..."
        chown -R 1000:1000 "${AXLAP_BASE_DIR}/data/opencti_data/es_octi" || log "Warning: Could not chown opencti_data/es_octi. Check permissions."
        chmod -R g+w "${AXLAP_BASE_DIR}/data/opencti_data/es_octi" || log "Warning: Could not chmod opencti_data/es_octi."
    fi
}

setup_axlap_source() {
    log "Setting up AXLAP source files in ${AXLAP_BASE_DIR}..."
    # Determine if the script is running from within a git clone or a standalone copy
    SCRIPT_REAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

    if [ -d "${SCRIPT_REAL_DIR}/.git" ] && [ "${SCRIPT_REAL_DIR}" != "${AXLAP_BASE_DIR}" ]; then
        log "Copying AXLAP git repository from ${SCRIPT_REAL_DIR} to ${AXLAP_BASE_DIR}..."
        # Use rsync to copy, excluding .git if not desired, or include if it's the primary copy
        rsync -av --exclude='.git/' --exclude='data/' --exclude='logs/' --exclude='venv/' "${SCRIPT_REAL_DIR}/" "${AXLAP_BASE_DIR}/" >> "${LOG_FILE}" 2>&1
    elif [ ! -d "${AXLAP_BASE_DIR}/docker-compose.yml" ]; then # If target doesn't look like AXLAP
        if [ -d "${SCRIPT_REAL_DIR}/docker-compose.yml" ]; then # And current script dir does
             log "Copying AXLAP files from ${SCRIPT_REAL_DIR} to ${AXLAP_BASE_DIR}..."
             rsync -av --exclude='data/' --exclude='logs/' --exclude='venv/' "${SCRIPT_REAL_DIR}/" "${AXLAP_BASE_DIR}/" >> "${LOG_FILE}" 2>&1
        else
            log "Cloning AXLAP repository from ${AXLAP_REPO_URL} (branch: ${AXLAP_BRANCH})..."
            git clone --branch "${AXLAP_BRANCH}" "${AXLAP_REPO_URL}" "${AXLAP_BASE_DIR}" >> "${LOG_FILE}" 2>&1
        fi
    else
        log "AXLAP files seem to be already in place at ${AXLAP_BASE_DIR}."
    fi
    cd "${AXLAP_BASE_DIR}"
}

configure_env_file() {
    log "Creating and populating .env file: ${ENV_FILE}"
    # Create .env file for docker-compose
    # Ensure this file has restricted permissions
    rm -f "${ENV_FILE}"
    touch "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"

    echo "# AXLAP Environment Configuration - Auto-generated by install.sh" > "${ENV_FILE}"
    echo "AXLAP_BASE_DIR=${AXLAP_BASE_DIR}" >> "${ENV_FILE}"
    echo "COMPOSE_PROJECT_NAME=axlap" >> "${ENV_FILE}" # Sets a project name for Docker Compose

    # Network configurations
    echo "CAPTURE_INTERFACE_FROM_ENV=${CAPTURE_INTERFACE}" >> "${ENV_FILE}" # For Arkime capture, Suricata, Zeek
    echo "HOME_NETS_FROM_ENV=${HOME_NETS}" >> "${ENV_FILE}" # For Zeek networks.cfg
    # Suricata's HOME_NET needs to be in the format "[cidr1,cidr2]"
    SURICATA_HOME_NET_FORMATTED="[$(echo "${HOME_NETS}" | sed 's/,/, /g')]"
    echo "HOME_NETS_CONFIG_SURICATA=${SURICATA_HOME_NET_FORMATTED}" >> "${ENV_FILE}"

    # Secrets and Tokens
    echo "OPENCTI_ADMIN_EMAIL=${OPENCTI_ADMIN_EMAIL}" >> "${ENV_FILE}"
    echo "OPENCTI_ADMIN_PASSWORD=${OPENCTI_ADMIN_PASSWORD}" >> "${ENV_FILE}"
    echo "OPENCTI_ADMIN_TOKEN=${OPENCTI_ADMIN_TOKEN}" >> "${ENV_FILE}"

    echo "MINIO_ROOT_USER=${MINIO_ROOT_USER}" >> "${ENV_FILE}"
    echo "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" >> "${ENV_FILE}"

    echo "ARKIME_PASSWORD_SECRET=${ARKIME_PASSWORD_SECRET}" >> "${ENV_FILE}"
    # ARKIME_ELASTICSEARCH is set directly in docker-compose.yml for arkime-viewer/capture

    # Connector specific (ensure these are used in docker-compose.yml for connectors)
    echo "CONNECTOR_EXPORT_FILE_STIX_ID=${CONNECTOR_EXPORT_FILE_STIX_ID}" >> "${ENV_FILE}"
    echo "CONNECTOR_IMPORT_FILE_STIX_ID=${CONNECTOR_IMPORT_FILE_STIX_ID}" >> "${ENV_FILE}"
    echo "CONNECTOR_MISP_ID=${CONNECTOR_MISP_ID}" >> "${ENV_FILE}"
    if [ -n "${MISP_URL}" ] && [ -n "${MISP_KEY}" ]; then
        echo "MISP_URL=${MISP_URL}" >> "${ENV_FILE}"
        echo "MISP_KEY=${MISP_KEY}" >> "${ENV_FILE}"
    else
        log "MISP_URL or MISP_KEY not set. MISP connector will require manual configuration if used."
        echo "# MISP_URL=" >> "${ENV_FILE}"
        echo "# MISP_KEY=" >> "${ENV_FILE}"
    fi

    # Zeek related env vars for Dockerfile or runtime
    echo "ZEEK_INTERFACE_FROM_ENV=${CAPTURE_INTERFACE}" >> "${ENV_FILE}"
    # LOCAL_NETS_FROM_ENV is used by Zeek Dockerfile entrypoint to update local.zeek or networks.cfg
    echo "LOCAL_NETS_FROM_ENV=${HOME_NETS}" >> "${ENV_FILE}"

    # Suricata related env vars for Dockerfile or runtime
    echo "SURICATA_INTERFACE_FROM_ENV=${CAPTURE_INTERFACE}" >> "${ENV_FILE}"
    # HOME_NETS_CONFIG_SURICATA is already set above for Suricata entrypoint

    log ".env file created successfully."
}

update_configs() {
    log "Updating service configuration files..."

    # Arkime config.ini
    # passwordSecret and elasticsearch URL are now primarily driven by .env through docker-compose for Arkime service
    # The interface for live capture is also passed via .env to CAPTURE_INTERFACE_FROM_ENV
    # So, config.ini should use these env vars: ${ARKIME_PASSWORD_SECRET}, ${ARKIME_ELASTICSEARCH}, ${CAPTURE_INTERFACE_FROM_ENV}
    # Ensure config.ini template in the repo uses these placeholders.
    # Example: sed -i "s|^elasticsearch=.*|elasticsearch=\${ARKIME_ELASTICSEARCH:-http://axlap-elasticsearch:9200}|" "${AXLAP_BASE_DIR}/config/arkime/config.ini"
    # This is better handled if config.ini is templated to use env vars directly. Assuming it is.

    # Zeek networks.cfg
    # This is populated by the Zeek container's entrypoint script using ZEEK_HOME_NETS_FROM_ENV or similar.
    # Or, we can write it directly here.
    ZEEK_NETWORKS_CFG="${AXLAP_BASE_DIR}/config/zeek/networks.cfg"
    log "Configuring Zeek networks.cfg: ${ZEEK_NETWORKS_CFG}"
    echo "# AXLAP Zeek Local Networks - Auto-generated by install.sh" > "${ZEEK_NETWORKS_CFG}"
    echo "# Used by Zeek to distinguish local traffic from remote." >> "${ZEEK_NETWORKS_CFG}"
    echo "\${HOME_NETS_FROM_ENV}" >> "${ZEEK_NETWORKS_CFG}" # Placeholder to be resolved by Zeek entrypoint or this script
    # Let's resolve it here directly from $HOME_NETS
    echo "" > "${ZEEK_NETWORKS_CFG}" # Clear it first
    IFS=',' read -ra ADDR <<< "$HOME_NETS"
    for net_cidr in "${ADDR[@]}"; do
        echo "${net_cidr}" >> "${ZEEK_NETWORKS_CFG}"
    done
    log "Zeek networks.cfg configured with: ${HOME_NETS}"

    # Zeek local.zeek - ensure it loads custom plugins and sets logdir
    # The path /opt/axlap/zeek_plugins is hardcoded in local.zeek, ensure it matches.
    # Log::logdir = "/var/log/zeek_json" is also in local.zeek.
    # Copy the template local.zeek to the site directory if not already there.
    if [ -f "${AXLAP_BASE_DIR}/config/zeek/local.zeek" ] && [ ! -f "${AXLAP_BASE_DIR}/config/zeek/site/local.zeek" ]; then
        cp "${AXLAP_BASE_DIR}/config/zeek/local.zeek" "${AXLAP_BASE_DIR}/config/zeek/site/local.zeek"
        log "Copied local.zeek to site configuration."
    fi
    # Update Zeek node.cfg interface placeholder (though entrypoint should handle it too)
    sed -i "s|^\s*interface=.*|interface=\${ZEEK_INTERFACE_FROM_ENV:-eth0}|" "${AXLAP_BASE_DIR}/config/zeek/node.cfg"


    # Suricata suricata.yaml - HOME_NET and interface are handled by its entrypoint script via ENV vars from .env
    # Ensure suricata.yaml uses placeholders like ${HOME_NETS_CONFIG_SURICATA} and ${SURICATA_INTERFACE_FROM_ENV}
    # The provided suricata.yaml seems to use these.

    # AXLAP TUI config
    TUI_CONFIG_FILE="${AXLAP_BASE_DIR}/config/axlap_tui_config.ini"
    log "Updating AXLAP TUI config: ${TUI_CONFIG_FILE}"
    # Replace placeholder for OpenCTI API Key
    sed -i "s|api_key = .*|api_key = \${OPENCTI_ADMIN_TOKEN_FROM_ENV}|" "${TUI_CONFIG_FILE}"
    # Ensure paths in TUI config are relative to AXLAP_BASE_DIR or absolute using it
    # These paths are for the TUI running on the host, accessing scripts/plugins within AXLAP_BASE_DIR
    sed -i "s|^train_script_path = .*|train_script_path = ${AXLAP_BASE_DIR}/scripts/train_ml_model.sh|" "${TUI_CONFIG_FILE}"
    sed -i "s|^update_script_path = .*|update_script_path = ${AXLAP_BASE_DIR}/scripts/update_rules_and_feeds.sh|" "${TUI_CONFIG_FILE}"
    sed -i "s|^zeek_plugins_dir = .*|zeek_plugins_dir = ${AXLAP_BASE_DIR}/src/zeek_plugins/|" "${TUI_CONFIG_FILE}"
    sed -i "s|^zeek_plugin_config_dir = .*|zeek_plugin_config_dir = ${AXLAP_BASE_DIR}/config/zeek/plugin_configs/|" "${TUI_CONFIG_FILE}"
    sed -i "s|^zeek_local_script = .*|zeek_local_script = ${AXLAP_BASE_DIR}/config/zeek/site/local.zeek|" "${TUI_CONFIG_FILE}"
    # Ensure Elasticsearch host/port for TUI is 127.0.0.1:9200 as per docker-compose port mapping
    sed -i "/^\[elasticsearch\]/,/^\[/ s|^host = .*|host = 127.0.0.1|" "${TUI_CONFIG_FILE}"
    sed -i "/^\[elasticsearch\]/,/^\[/ s|^port = .*|port = 9200|" "${TUI_CONFIG_FILE}"
    # Ensure Arkime host/port for TUI is 127.0.0.1:8005
    sed -i "/^\[arkime\]/,/^\[/ s|^host = .*|host = 127.0.0.1|" "${TUI_CONFIG_FILE}"
    sed -i "/^\[arkime\]/,/^\[/ s|^port = .*|port = 8005|" "${TUI_CONFIG_FILE}"
    # Ensure OpenCTI URL for TUI is 127.0.0.1:8080
    sed -i "/^\[opencti\]/,/^\[/ s|^url = .*|url = http://127.0.0.1:8080|" "${TUI_CONFIG_FILE}"

    log "Service configurations updated."
}

wait_for_elasticsearch() {
    local es_host_port="$1"
    local service_name="$2"
    log "Waiting for ${service_name} Elasticsearch (${es_host_port}) to be healthy..."
    MAX_WAIT=300 # 5 minutes
    COUNT=0
    log "Waiting for ${service_name} Elasticsearch (${es_host_port}) to be healthy..."
    # Corrected service name in the log guidance for docker-compose logs
    local docker_compose_service_name="axlap-elasticsearch" # Actual service name for docker-compose
    if [[ "${service_name}" == *"OpenCTI"* ]]; then
        docker_compose_service_name="axlap-opencti-es"
    fi

    while ! curl -s -k "http://${es_host_port}/_cluster/health?wait_for_status=yellow&timeout=10s" > /dev/null 2>&1; do
        sleep 10
        COUNT=$((COUNT + 10))
        if [ "$COUNT" -ge "$MAX_WAIT" ]; then
            log "ERROR: ${service_name} Elasticsearch (${es_host_port}) did not become healthy in time."
            log "Run 'sudo docker-compose -f \"${DOCKER_COMPOSE_FILE}\" logs ${docker_compose_service_name}' for details."
            return 1 # Failure
        fi
        printf "."
    done
    echo # Newline after dots
    log "${service_name} Elasticsearch (${es_host_port}) is up and healthy."
    return 0 # Success
}

initialize_arkime() {
    log "Initializing Arkime database in Elasticsearch..."
    # Wait a bit for Arkime viewer to be fully ready after ES is up.
    sleep 15

    # Check if db.pl exists and then run init
    if docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-arkime-viewer test -f /opt/arkime/db/db.pl; then
        # Attempt non-interactive init. Arkime versions vary in how this works.
        # Sending "INIT" on stdin is a common method.
        log "Attempting to initialize Arkime database (sending INIT)..."
        if echo "INIT" | docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-arkime-viewer /opt/arkime/db/db.pl http://axlap-elasticsearch:9200 init >> "${LOG_FILE}" 2>&1; then
            log "Arkime database initialization command completed."
        else
            log "WARNING: Arkime database initialization command failed or had non-zero exit. Check logs."
        fi

        log "Adding Arkime admin user (admin / AdminAXLAPPassw0rd)..."
        if docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-arkime-viewer /opt/arkime/bin/arkime_add_user.sh admin "AXLAP Admin" "AdminAXLAPPassw0rd" --admin >> "${LOG_FILE}" 2>&1; then
            log "Arkime admin user 'admin' added with default password."
            log "IMPORTANT: Change this password via Arkime UI (http://127.0.0.1:8005) after first login."
        else
            log "ERROR: Failed to add Arkime admin user. Check logs."
        fi
    else
        log "WARNING: Arkime db.pl not found in viewer container. Skipping automatic DB init. Arkime might auto-init or require manual setup."
    fi
}

wait_for_opencti() {
    log "Waiting for OpenCTI platform (http://127.0.0.1:8080) to be available..."
    MAX_WAIT_OPENCTI=600 # 10 minutes, OpenCTI can take a while
    COUNT=0
    # Check for a 200 OK on the /graphql endpoint with a basic query
    # Ensure the curl command is robust and quoting is correct
    OPENCTI_GRAPHQL_URL="http://127.0.0.1:8080/graphql"
    GRAPHQL_QUERY='{"query":"{ about { version } }"}'

    while ! curl -s -k -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" --data "${GRAPHQL_QUERY}" "${OPENCTI_GRAPHQL_URL}" | grep -q "200"; do
        sleep 15
        COUNT=$((COUNT + 15))
        if [ "$COUNT" -ge "$MAX_WAIT_OPENCTI" ]; then
            log "ERROR: OpenCTI platform (${OPENCTI_GRAPHQL_URL}) did not become available in time."
            log "Run 'sudo docker-compose -f \"${DOCKER_COMPOSE_FILE}\" logs opencti opencti-worker axlap-opencti-es' for details."
            return 1
        fi
        printf "o"
    done
    echo # Newline
    log "OpenCTI platform appears to be up."
    log "Admin user: ${OPENCTI_ADMIN_EMAIL}, Password: ${OPENCTI_ADMIN_PASSWORD}"
    log "API Token: ${OPENCTI_ADMIN_TOKEN}"
    log "IMPORTANT: Change default OpenCTI admin password after first login."
    return 0
}

setup_python_venv() {
    log "Setting up Python virtual environment for TUI and ML tools..."
    if [ ! -f "${AXLAP_BASE_DIR}/venv/bin/activate" ]; then
        log "Creating Python virtual environment at ${AXLAP_BASE_DIR}/venv..."
        python3 -m venv "${AXLAP_BASE_DIR}/venv" >> "${LOG_FILE}" 2>&1
    else
        log "Python virtual environment already exists."
    fi

    # shellcheck source=/dev/null
    source "${AXLAP_BASE_DIR}/venv/bin/activate"
    log "Upgrading pip..."
    pip install --upgrade pip >> "${LOG_FILE}" 2>&1
    log "Installing TUI requirements from src/tui/requirements.txt..."
    pip install elasticsearch >> "${LOG_FILE}" 2>&1
    log installed "elasticsearch" package for Python
    pip install -r "${AXLAP_BASE_DIR}/src/tui/requirements.txt" >> "${LOG_FILE}" 2>&1
    log "Installing ML Engine requirements from src/ml_engine/requirements.txt..."
    pip install -r "${AXLAP_BASE_DIR}/src/ml_engine/requirements.txt" >> "${LOG_FILE}" 2>&1
    deactivate
    log "Python virtual environment setup complete."
}

setup_systemd_services() {
    log "Setting up systemd services for AXLAP..."

    SYSTEMD_AXLAP_SERVICE_FILE="/etc/systemd/system/axlap.service"
    cat << EOF > "${SYSTEMD_AXLAP_SERVICE_FILE}"
[Unit]
Description=AXLAP - Autonomous XKeyscore-Like Analysis Platform
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=true
EnvironmentFile=${ENV_FILE}
WorkingDirectory=${AXLAP_BASE_DIR}
ExecStart=${AXLAP_BASE_DIR}/scripts/start_axlap.sh
ExecStop=${AXLAP_BASE_DIR}/scripts/stop_axlap.sh
StandardOutput=append:${LOG_DIR}/axlap-systemd.log
StandardError=append:${LOG_DIR}/axlap-systemd.err.log
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    SYSTEMD_AXLAP_UPDATES_SERVICE_FILE="/etc/systemd/system/axlap-updates.service"
    cat << EOF > "${SYSTEMD_AXLAP_UPDATES_SERVICE_FILE}"
[Unit]
Description=AXLAP Rules and Threat Feeds Updater
After=axlap.service

[Service]
Type=oneshot
EnvironmentFile=${ENV_FILE}
WorkingDirectory=${AXLAP_BASE_DIR}
ExecStart=${AXLAP_BASE_DIR}/scripts/update_rules_and_feeds.sh
StandardOutput=append:${LOG_DIR}/axlap-updates.log
StandardError=append:${LOG_DIR}/axlap-updates.err.log
EOF

    SYSTEMD_AXLAP_UPDATES_TIMER_FILE="/etc/systemd/system/axlap-updates.timer"
    cat << EOF > "${SYSTEMD_AXLAP_UPDATES_TIMER_FILE}"
[Unit]
Description=Run AXLAP updater daily at 3 AM

[Timer]
OnCalendar=daily
AccuracySec=1h # Allow some flexibility
RandomizedDelaySec=600 # Add random delay up to 10 minutes
Persistent=true # Run on next boot if missed
Unit=axlap-updates.service

[Install]
WantedBy=timers.target
EOF

    log "Reloading systemd daemon, enabling and starting AXLAP services..."
    systemctl daemon-reload >> "${LOG_FILE}" 2>&1
    systemctl enable axlap.service >> "${LOG_FILE}" 2>&1
    systemctl enable axlap-updates.timer >> "${LOG_FILE}" 2>&1
    # Services are started by docker-compose up earlier.
    # systemctl start axlap.service will run start_axlap.sh which does 'docker-compose up -d'
    # This is fine, 'up -d' is idempotent.
    systemctl restart axlap.service >> "${LOG_FILE}" 2>&1 # Ensure it's (re)started correctly with systemd
    systemctl start axlap-updates.timer >> "${LOG_FILE}" 2>&1
    log "Systemd services configured."
}

# --- Main Installation Steps ---
main() {
    # Create base directory and log directory/file first
    mkdir -p "${AXLAP_BASE_DIR}" # Ensure base directory exists
    mkdir -p "${LOG_DIR}"       # Ensure log directory exists
    touch "${LOG_FILE}" && chmod 600 "${LOG_FILE}" # Create log file with restricted permissions

    check_root
    check_os

    log "AXLAP installation started. Log file: ${LOG_FILE}"

    log "Step 1: Install System Dependencies..."
    apt-get update -y >> "${LOG_FILE}" 2>&1
    apt-get install -y --no-install-recommends \
        git curl docker.io docker-compose python3 python3-pip python3-venv python3-dev \
        make iptables apparmor-utils uuid-runtime openssl jq apt-transport-https \
        ca-certificates gnupg lsb-release libpcap-dev libcurl4-openssl-dev rsync yq net-tools htop \
        ncurses-dev # For TUI if building any C extensions, or for general dev
        >> "${LOG_FILE}" 2>&1
    check_command "docker"
    check_command "docker-compose"
    check_command "git"
    check_command "python3"
    check_command "pip3"
    check_command "yq" # Useful for YAML manipulation if needed later
    log "System dependencies installed."

    log "Step 2: Ensure Docker service is running..."
    if ! systemctl is-active --quiet docker; then
        log "Starting Docker service..."
        systemctl start docker >> "${LOG_FILE}" 2>&1
        systemctl enable docker >> "${LOG_FILE}" 2>&1
    fi
    log "Docker service is active."
    log "Docker version: $(docker --version)"
    log "Docker Compose version: $(docker-compose --version)"

    log "Step 3: Setup AXLAP Source Files..."
    setup_axlap_source
    log "AXLAP source files setup in ${AXLAP_BASE_DIR}."

    log "Step 4: Configure Environment File (.env)..."
    configure_env_file
    log ".env file configured."

    log "Step 5: Update Service Configuration Files..."
    update_configs
    log "Service configuration files updated."

    log "Step 6: Set Executable Permissions for Scripts..."
    find "${AXLAP_BASE_DIR}/scripts" -name "*.sh" -exec chmod +x {} \;
    if [ -f "${AXLAP_BASE_DIR}/src/tui/axlap_tui.py" ]; then
        chmod +x "${AXLAP_BASE_DIR}/src/tui/axlap_tui.py"
    fi
    log "Script permissions set."

    log "Step 7: Build and Pull Docker Images..."
    log "Building custom Docker images (this may take a while)..."
    # Show build output directly to console for easier debugging if it fails
    # The full output will still be in LOG_FILE if the script continues past this or if tee is used.
    echo "---------------------------------------------------------------------"
    echo " Docker Compose Build Output (also logged to ${LOG_FILE})            "
    echo "---------------------------------------------------------------------"
    if docker-compose -f "${DOCKER_COMPOSE_FILE}" build --pull 2>&1 | tee -a "${LOG_FILE}"; then
        log "Custom Docker images built successfully."
    else
        log "ERROR: Docker Compose build failed. See output above and check ${LOG_FILE} for full details."
        echo "ERROR: Docker Compose build failed. Check the output above and the log file: ${LOG_FILE}" >&2
        exit 1 # Explicitly exit if build fails
    fi
    echo "---------------------------------------------------------------------"

    log "Pulling remaining official Docker images (if any specified without a local build context)..."
    if docker-compose -f "${DOCKER_COMPOSE_FILE}" pull >> "${LOG_FILE}" 2>&1; then
        log "Docker images pulled successfully."
    else
        log "WARNING: Docker Compose pull command encountered an issue. Some images might not be up-to-date. Check ${LOG_FILE}."
        # Not exiting here as some images might have pulled successfully, or it might be non-critical.
    fi
    log "Docker images are ready."

    log "Step 8: Start All AXLAP Services..."
    # The .env file is automatically picked up by docker-compose in the same directory
    docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d >> "${LOG_FILE}" 2>&1
    log "AXLAP services are starting in detached mode."

    log "Step 9: Wait for Core Services and Initialize..."
    wait_for_elasticsearch "127.0.0.1:9200" "Main (axlap-elasticsearch)" || log "Continuing despite Main ES not becoming healthy."
    # OpenCTI's ES is not directly exposed, rely on OpenCTI's own health.

    initialize_arkime # Initializes Arkime DB and adds admin user

    wait_for_opencti || log "Continuing despite OpenCTI not becoming fully available."

    log "Step 10: Setup Python Virtual Environment for Host Tools (TUI, ML scripts)..."
    setup_python_venv

    log "Step 11: Initial ML Model Training (Optional)..."
    log "ML Model training can be initiated via TUI or by running: sudo ${AXLAP_BASE_DIR}/scripts/train_ml_model.sh"
    log "Ensure some network data has been processed by Zeek and ingested into Elasticsearch before first training."

    log "Step 12: Setup Systemd Services..."
    setup_systemd_services

    log "Step 13: Security Considerations..."
    log "Basic iptables rules are for host protection. Docker manages its own container network rules."
    log "Consider using 'ufw' or a more comprehensive firewall setup for the host."
    # Example: ufw allow ssh; ufw allow http; ufw allow https; ufw default deny incoming; ufw enable
    log "Ensure AppArmor is enabled on the host. Custom AppArmor profiles for containers can be added for enhanced security."
    if systemctl is-active --quiet apparmor; then
        log "AppArmor service is active."
    else
        log "WARNING: AppArmor service is not active. Consider enabling it: sudo systemctl enable --now apparmor"
    fi

    log "Step 14: Final Instructions..."
    echo "" | tee -a "${LOG_FILE}"
    echo "---------------------------------------------------------------------" | tee -a "${LOG_FILE}"
    echo " AXLAP Installation Completed!" | tee -a "${LOG_FILE}"
    echo "---------------------------------------------------------------------" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Base Directory: ${AXLAP_BASE_DIR}" | tee -a "${LOG_FILE}"
    echo "Capture Interface: ${CAPTURE_INTERFACE}" | tee -a "${LOG_FILE}"
    echo "Log File: ${LOG_FILE}" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Access Services:" | tee -a "${LOG_FILE}"
    echo "  - AXLAP TUI: cd ${AXLAP_BASE_DIR} && source venv/bin/activate && python3 src/tui/axlap_tui.py" | tee -a "${LOG_FILE}"
    echo "  - Arkime UI: http://127.0.0.1:8005 (Login: admin / AdminAXLAPPassw0rd - CHANGE THIS!)" | tee -a "${LOG_FILE}"
    echo "  - OpenCTI UI: http://127.0.0.1:8080 (Login: ${OPENCTI_ADMIN_EMAIL} / ${OPENCTI_ADMIN_PASSWORD} - CHANGE THIS!)" | tee -a "${LOG_FILE}"
    echo "    OpenCTI API Token (for TUI config or scripts): ${OPENCTI_ADMIN_TOKEN}" | tee -a "${LOG_FILE}"
    echo "  - Elasticsearch (Main): http://127.0.0.1:9200" | tee -a "${LOG_FILE}"
    echo "  - MinIO Console (OpenCTI S3): http://127.0.0.1:9001 (User: ${MINIO_ROOT_USER} / Pass: ${MINIO_ROOT_PASSWORD} - CHANGE THIS!)" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Service Management (Systemd):" | tee -a "${LOG_FILE}"
    echo "  - Start AXLAP: sudo systemctl start axlap.service" | tee -a "${LOG_FILE}"
    echo "  - Stop AXLAP: sudo systemctl stop axlap.service" | tee -a "${LOG_FILE}"
    echo "  - Status: sudo systemctl status axlap.service" | tee -a "${LOG_FILE}"
    echo "  - Logs: sudo journalctl -u axlap.service -f" | tee -a "${LOG_FILE}"
    echo "  - Docker Logs: cd ${AXLAP_BASE_DIR} && sudo docker-compose logs -f <service_name>" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
    echo "Important Notes:" | tee -a "${LOG_FILE}"
    echo "  - REVIEW AND CHANGE ALL DEFAULT PASSWORDS AND SECRETS IMMEDIATELY!" | tee -a "${LOG_FILE}"
    echo "  - Ensure network traffic is correctly mirrored/spanned to the '${CAPTURE_INTERFACE}' interface." | tee -a "${LOG_FILE}"
    echo "  - Monitor disk space in '${AXLAP_BASE_DIR}/data'." | tee -a "${LOG_FILE}"
    echo "  - Customize Zeek scripts in '${AXLAP_BASE_DIR}/src/zeek_plugins/' and '${AXLAP_BASE_DIR}/config/zeek/site/local.zeek'." | tee -a "${LOG_FILE}"
    echo "  - Add custom Suricata rules to '${AXLAP_BASE_DIR}/config/suricata/rules/local.rules' (or similar path configured in suricata.yaml)." | tee -a "${LOG_FILE}"
    echo "---------------------------------------------------------------------" | tee -a "${LOG_FILE}"
}

# --- Script Execution ---
main "$@"

exit 0
