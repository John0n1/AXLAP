#!/bin/bash
# Updates Suricata rules, triggers OpenCTI connector runs (conceptual), and updates Zeek intel files.

# SCRIPT_DIR is defined in axlap_common_env.sh if sourced, otherwise set it here
if [ -z "${SCRIPT_DIR_COMMON}" ]; then
    CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
else
    CURRENT_SCRIPT_DIR="${SCRIPT_DIR_COMMON}"
fi
# shellcheck source=./axlap_common_env.sh
source "${CURRENT_SCRIPT_DIR}/axlap_common_env.sh"

LOG_FILE_UPDATES="${LOG_DIR}/axlap_updates.log"

log_update() {
    _log_message_common "$1" # Will also log to axlap_updates.log
}

# --- Suricata Rule Update ---
update_suricata_rules() {
    log_update "Updating Suricata rules..."
    cd "${AXLAP_BASE_DIR}" || { log_update "ERROR: Failed to cd to ${AXLAP_BASE_DIR}"; return 1; }

    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" ps -q axlap-suricata 2>/dev/null | grep -q .; then
        log_update "ERROR: axlap-suricata container is not running. Cannot update rules."
        return 1
    fi

    # The Suricata container's entrypoint already runs suricata-update on start.
    # Forcing an update here. Ensure suricata-update uses the correct config.
    # The entrypoint copies /etc/suricata/suricata.yaml to /tmp/suricata.yaml and modifies it.
    # We should ideally trigger that logic or ensure this call is compatible.
    # A simple `suricata-update` might use default paths not aligned with the running instance's /tmp/suricata.yaml