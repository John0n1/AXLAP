FROM ubuntu:22.04

ARG ZEEK_VERSION=5.0.8 # Consider using a newer stable version if available and compatible
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    make \
    swig \
    libssl-dev \
    libgeoip-dev \
    libpcap-dev \
    libmaxminddb-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-git \
    python3-semantic-version \
    zlib1g-dev \
    curl \
    git \
    bison \
    flex \
    # For Zeek 6+ Python bindings, ensure Python version is >= 3.7
    # Additional dependencies for plugins might be needed here (e.g., libyara-dev)
    && rm -rf /var/lib/apt/lists/*

# Install Zeek from source
RUN mkdir -p /opt/zeek_src && cd /opt/zeek_src && \
    curl -sSL "https://download.zeek.org/zeek-${ZEEK_VERSION}.tar.gz" -o "zeek-${ZEEK_VERSION}.tar.gz" && \
    tar -xzf "zeek-${ZEEK_VERSION}.tar.gz" && \
    cd "zeek-${ZEEK_VERSION}" && \
    # --disable-broker if not using Broker for clustering (common for single node AXLAP)
    # --enable-json-logs is default in newer Zeeks but good to be explicit
    # --enable-af-packet for AF_PACKET v3 support
    ./configure --prefix=/usr/local/zeek --disable-broker --enable-json-logs --enable-af-packet && \
    make -j$(nproc) && \
    make install && \
    cd / && rm -rf /opt/zeek_src

ENV PATH="/usr/local/zeek/bin:${PATH}"

# Create necessary directories for Zeek runtime and AXLAP specifics
# These paths should align with volume mounts in docker-compose.yml
RUN mkdir -p /usr/local/zeek/spool \
    && mkdir -p /usr/local/zeek/logs \
    && mkdir -p /var/log/zeek_json \
    && mkdir -p /data/pcap \
    && mkdir -p /opt/axlap/zeek_plugins \
    && mkdir -p /opt/axlap/threat_intel

# ZeekControl setup - `zeekctl install` sets up initial configs like zeekctl.cfg
# It uses /usr/local/zeek/etc/zeekctl.cfg.template
RUN /usr/local/zeek/bin/zeekctl install

# Environment variables from .env via docker-compose
ENV ZEEK_INTERFACE="${ZEEK_INTERFACE_FROM_ENV:-eth0}"
ENV LOCAL_NETS="${LOCAL_NETS_FROM_ENV:-192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"

# Modify zeekctl.cfg for AXLAP specifics
# LogDir and SpoolDir are standard Zeek log/spool locations, not where JSON logs go.
# JSON log output dir is controlled by `Log::logdir` in local.zeek.
RUN sed -i "s|^LogDir.*|LogDir = /usr/local/zeek/logs|" /usr/local/zeek/etc/zeekctl.cfg && \
    sed -i "s|^SpoolDir.*|SpoolDir = /usr/local/zeek/spool|" /usr/local/zeek/etc/zeekctl.cfg && \
    echo "MailTo = root@localhost" >> /usr/local/zeek/etc/zeekctl.cfg && \
    echo "LogRotationInterval = 3600" >> /usr/local/zeek/etc/zeekctl.cfg
    # JsonLog::enable = T is for a specific zkg package, not core Zeek JSON logging.
    # Core JSON logging is enabled via `redef Log::default_log_writer = Log::WRITER_JSON;` in local.zeek.

# Entrypoint script to configure and start Zeek
COPY <<EOF /usr/local/bin/entrypoint.sh
#!/bin/bash
set -e

echo "[$(date)] AXLAP Zeek Entrypoint Initializing..."
LOG_INIT_ZEEK="/var/log/zeek_json/init.log" # Log to a file in the mounted log volume

echo "Zeek Interface: ${ZEEK_INTERFACE}" | tee -a "${LOG_INIT_ZEEK}"
echo "Local Networks: ${LOCAL_NETS}" | tee -a "${LOG_INIT_ZEEK}"

# Configure Zeek interface in node.cfg
# node.cfg is typically mounted from the host at /usr/local/zeek/etc/node.cfg
# If it's not mounted but copied during build, this modification is fine.
# If mounted, changes here might not persist if the mounted file is read-only or overwritten.
# Best practice: mount node.cfg and ensure it uses ${ZEEK_INTERFACE_FROM_ENV} or this script updates the mounted copy.
# For now, assume it's okay to modify the one in the container, which might be a copy or a mount.
if [ -f /usr/local/zeek/etc/node.cfg ]; then
    sed -i "s|^interface=.*|interface=${ZEEK_INTERFACE}|" /usr/local/zeek/etc/node.cfg
    echo "Updated interface in /usr/local/zeek/etc/node.cfg to ${ZEEK_INTERFACE}" | tee -a "${LOG_INIT_ZEEK}"
else
    echo "WARNING: /usr/local/zeek/etc/node.cfg not found. Interface configuration might be incorrect." | tee -a "${LOG_INIT_ZEEK}"
fi

# Configure networks.cfg with LOCAL_NETS
# networks.cfg is typically mounted from host at /usr/local/zeek/etc/networks.cfg
if [ -f /usr/local/zeek/etc/networks.cfg ]; then
    echo "# Networks configuration for Zeek - populated by entrypoint.sh" > /usr/local/zeek/etc/networks.cfg
    IFS=',' read -ra NET_ARRAY <<< "${LOCAL_NETS}"
    for net_cidr in "${NET_ARRAY[@]}"; do
        echo "${net_cidr}" >> /usr/local/zeek/etc/networks.cfg
    done
    echo "Updated /usr/local/zeek/etc/networks.cfg with: ${LOCAL_NETS}" | tee -a "${LOG_INIT_ZEEK}"
else
    echo "WARNING: /usr/local/zeek/etc/networks.cfg not found. Local network configuration might be incorrect." | tee -a "${LOG_INIT_ZEEK}"
fi

# Ensure site/local.zeek is present (mounted from host)
if [ ! -f "/usr/local/zeek/share/zeek/site/local.zeek" ]; then
    echo "ERROR: /usr/local/zeek/share/zeek/site/local.zeek not found. Mount your site configuration." | tee -a "${LOG_INIT_ZEEK}"
    exit 1
fi

# Ensure custom plugin directory is accessible (mounted from host)
if [ ! -d "/opt/axlap/zeek_plugins" ]; then
    echo "Warning: Custom plugin directory /opt/axlap/zeek_plugins not found (expected to be mounted)." | tee -a "${LOG_INIT_ZEEK}"
fi

# Ensure log directory for JSON logs exists and has correct permissions if Zeek runs as non-root.
# ZeekControl often runs workers as user 'zeek'.
mkdir -p /var/log/zeek_json
if id zeek &>/dev/null; then
    chown -R zeek:zeek /var/log/zeek_json || echo "Warning: Could not chown /var/log/zeek_json for user zeek." | tee -a "${LOG_INIT_ZEEK}"
    chown -R zeek:zeek /usr/local/zeek/spool || echo "Warning: Could not chown /usr/local/zeek/spool for user zeek." | tee -a "${LOG_INIT_ZEEK}"
fi

# Check zeekctl configuration. `zeekctl install` should have been run during build.
# `zeekctl check` can identify issues before deploying.
echo "Running 'zeekctl check'..." | tee -a "${LOG_INIT_ZEEK}"
if ! /usr/local/zeek/bin/zeekctl check; then
    echo "WARNING: 'zeekctl check' reported issues. Attempting to deploy anyway..." | tee -a "${LOG_INIT_ZEEK}"
fi

# Deploy Zeek using zeekctl (starts Zeek processes)
echo "Deploying Zeek using 'zeekctl deploy'..." | tee -a "${LOG_INIT_ZEEK}"
/usr/local/zeek/bin/zeekctl deploy || { echo "ERROR: 'zeekctl deploy' failed. Check Zeek logs in /usr/local/zeek/spool/ and ${LOG_INIT_ZEEK}."; exit 1; }

echo "Zeek deployed successfully." | tee -a "${LOG_INIT_ZEEK}"

# Keep container running and tail relevant logs for `docker logs`
# Tailing current.log from manager and all .log files in the JSON output directory.
echo "Tailing Zeek logs. Main Zeek logs are in /usr/local/zeek/spool/manager/ and JSON logs in /var/log/zeek_json/..." | tee -a "${LOG_INIT_ZEEK}"
tail -F /usr/local/zeek/spool/manager/current.log /usr/local/zeek/spool/manager/*.log /var/log/zeek_json/*.log /var/log/zeek_json/*/*.log 2>/dev/null &

# Keep the entrypoint script running; Zeek processes are managed by zeekctl in background.
# A common way to keep a script running is to wait on the child process (tail)
wait %1
# If tail exits, the container will stop. This is usually desired.
echo "Zeek entrypoint finished or tail process ended." | tee -a "${LOG_INIT_ZEEK}"

EOF

RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# CMD is not needed as ENTRYPOINT handles the Zeek lifecycle via zeekctl and tailing logs.
