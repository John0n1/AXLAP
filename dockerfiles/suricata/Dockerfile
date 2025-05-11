FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
    wget \
    curl \
    python3 \
    python3-pip \
    python3-yaml \
    libnet1 \
    libpcap-dev \
    libnetfilter-queue-dev \
    libnetfilter-conntrack-dev \
    libnfnetlink-dev \
    libluajit-5.1-dev \
    libjansson-dev \
    libmagic-dev \
    libmaxminddb-dev \
    libhtp-dev \
    jq \
    # For Rust based components if building Suricata from source or for some plugins
    # rustc cargo \
    && rm -rf /var/lib/apt/lists/*

# Install Suricata from PPA for a recent stable version
RUN add-apt-repository -y ppa:oisf/suricata-stable && \
    apt-get update && \
    apt-get install -y suricata suricata-update

# Create necessary directories
# /var/log/suricata for eve.json and suricata.log
# /etc/suricata for configuration (suricata.yaml, classification.config, etc.)
# /var/lib/suricata/rules for rules downloaded by suricata-update
# /var/run/suricata for PID file if Suricata manages it (though not typical for Docker foreground)
RUN mkdir -p /var/log/suricata \
    && mkdir -p /etc/suricata/rules \
    && mkdir -p /var/lib/suricata/rules \
    && mkdir -p /var/run/suricata

# Environment variables that will be passed from docker-compose.yml (via .env)
# These are defaults if not provided by the .env file.
ENV SURICATA_INTERFACE="${SURICATA_INTERFACE_FROM_ENV:-eth0}"
ENV HOME_NET_CONFIG="${HOME_NETS_CONFIG_SURICATA:-[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]}"

# Copy the entrypoint script into the container
COPY <<EOF /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e

echo "[$(date)] AXLAP Suricata Entrypoint Initializing..."

SURICATA_CONFIG_FILE_TEMPLATE="/etc/suricata/suricata.yaml" # This is the mounted config file
SURICATA_CONFIG_FILE_RUNTIME="/tmp/suricata_runtime.yaml"
LOG_INIT_SURICATA="/var/log/axlap_suricata_init/init.log" # Mounted from host

mkdir -p /var/log/axlap_suricata_init # Ensure log dir for this script exists

echo "Suricata Interface: \${SURICATA_INTERFACE}" | tee -a "\${LOG_INIT_SURICATA}"
echo "Home Net Config: \${HOME_NET_CONFIG}" | tee -a "\${LOG_INIT_SURICATA}"

if [ ! -f "\${SURICATA_CONFIG_FILE_TEMPLATE}" ]; then
    echo "ERROR: Suricata configuration template \${SURICATA_CONFIG_FILE_TEMPLATE} not found. Mount it correctly." | tee -a "\${LOG_INIT_SURICATA}"
    exit 1
fi

# Create a runtime copy of the configuration to modify
cp "\${SURICATA_CONFIG_FILE_TEMPLATE}" "\${SURICATA_CONFIG_FILE_RUNTIME}"

# Modify HOME_NET in the runtime configuration using yq for safety if available, else sed.
# suricata.yaml expects HOME_NET: "[cidr1, cidr2]"
if command -v yq &>/dev/null; then
    yq e ".vars.address-groups.HOME_NET = \"\${HOME_NET_CONFIG}\"" -i "\${SURICATA_CONFIG_FILE_RUNTIME}"
    echo "HOME_NET updated in \${SURICATA_CONFIG_FILE_RUNTIME} using yq." | tee -a "\${LOG_INIT_SURICATA}"
else
    echo "yq not found, using sed to update HOME_NET (less robust)." | tee -a "\${LOG_INIT_SURICATA}"
    # This sed command is fragile; yq is preferred.
    # It assumes HOME_NET is under vars.address-groups and is a simple string replacement.
    ESCAPED_HOME_NET_CONFIG=$(echo "\${HOME_NET_CONFIG}" | sed 's/[&/\\]/\\&/g') # Escape for sed
    sed -i "s|^ *HOME_NET:.*|HOME_NET: \"\${ESCAPED_HOME_NET_CONFIG}\"|" "\${SURICATA_CONFIG_FILE_RUNTIME}" 
fi

# Modify af-packet interface in the runtime configuration
# Assuming af-packet is the chosen capture method and interface is a top-level key under an af-packet list item.
if command -v yq &>/dev/null; then
    # This yq command assumes a structure like: af-packet: [{interface: eth0, ...}, ...]
    # It will update the first interface found. If multiple af-packet sections, adjust accordingly.
    yq e '(.af-packet.[] | select(.interface) | .interface) = "\${SURICATA_INTERFACE}"' -i "\${SURICATA_CONFIG_FILE_RUNTIME}"
    echo "AF-PACKET interface updated to \${SURICATA_INTERFACE} in \${SURICATA_CONFIG_FILE_RUNTIME} using yq." | tee -a "\${LOG_INIT_SURICATA}"
else
    echo "yq not found, using sed to update af-packet interface (less robust)." | tee -a "\${LOG_INIT_SURICATA}"
    sed -i "/af-packet:/,/^ *$/s|interface: .*|interface: \${SURICATA_INTERFACE}|" "\${SURICATA_CONFIG_FILE_RUNTIME}"
fi

# Ensure rule directories exist (suricata-update needs /var/lib/suricata/rules)
# /etc/suricata/rules is where suricata.yaml looks for local.rules and the main suricata.rules
mkdir -p /var/lib/suricata/rules
mkdir -p /etc/suricata/rules

# Update Suricata rules using suricata-update
# suricata-update uses the configuration file to determine rule paths and enabled/disabled rulesets.
echo "Updating Suricata rules with suricata-update..." | tee -a "\${LOG_INIT_SURICATA}"
suricata-update --suricata-conf "\${SURICATA_CONFIG_FILE_RUNTIME}" \
    --no-enable-conf # Do not modify enable.conf, manage via suricata.yaml or local sources
    # --no-disable-conf --no-modify-conf --no-drop-conf # These are less common to disable
    # Add --force if needed to overwrite local modifications to downloaded rules, but generally not recommended.
if [ $? -ne 0 ]; then
    echo "WARNING: suricata-update failed. Suricata might start with stale or no rules from suricata-update." | tee -a "\${LOG_INIT_SURICATA}"
fi

# suricata-update typically downloads to /var/lib/suricata/rules/suricata.rules
# The suricata.yaml is configured with default-rule-path: /etc/suricata/rules/
# and rule-files: [suricata.rules, local.rules].
# So, copy the updated rules to where suricata.yaml expects it.
if [ -f "/var/lib/suricata/rules/suricata.rules" ]; then
    cp /var/lib/suricata/rules/suricata.rules /etc/suricata/rules/suricata.rules
    echo "Copied updated suricata.rules to /etc/suricata/rules/" | tee -a "\${LOG_INIT_SURICATA}"
else
    echo "Warning: /var/lib/suricata/rules/suricata.rules not found after update. Check suricata-update output." | tee -a "\${LOG_INIT_SURICATA}"
fi

# Ensure custom local.rules exists (mounted from host or created empty)
if [ ! -f "/etc/suricata/rules/local.rules" ]; then
    echo "Creating empty /etc/suricata/rules/local.rules as it was not found (expected to be mounted)." | tee -a "\${LOG_INIT_SURICATA}"
    touch /etc/suricata/rules/local.rules
fi

# Start Suricata in the foreground for Docker logging
# Using -v for verbosity. EVE JSON logs to file for Filebeat.
# --user=root --group=root might be needed if running in a restrictive environment or with specific file permissions.
# However, Suricata often drops privileges itself if not run as root.
# If running privileged/host network, running as root initially is common.
echo "Starting Suricata on interface \${SURICATA_INTERFACE}..." | tee -a "\${LOG_INIT_SURICATA}"
exec /usr/bin/suricata -c "\${SURICATA_CONFIG_FILE_RUNTIME}" --af-packet="\${SURICATA_INTERFACE}" -v

EOF

RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# CMD is not needed as ENTRYPOINT execs Suricata
