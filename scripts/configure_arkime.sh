#!/bin/bash
# Arkime Configuration Helper Script

# SCRIPT_DIR is defined in axlap_common_env.sh if sourced, otherwise set it here
if [ -z "${SCRIPT_DIR_COMMON}" ]; then # SCRIPT_DIR_COMMON is set in the improved axlap_common_env.sh
    CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
else
    CURRENT_SCRIPT_DIR="${SCRIPT_DIR_COMMON}"
fi
# shellcheck source=./axlap_common_env.sh
source "${CURRENT_SCRIPT_DIR}/axlap_common_env.sh" # Sources AXLAP_BASE_DIR, DOCKER_COMPOSE_FILE, LOG_DIR, and .env vars

LOG_FILE_ARKIME_CONFIG="${LOG_DIR}/arkime_config.log"

log_arkime() {
    _log_message_common "$1" # Use common log function
}

add_arkime_user() {
    if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
        log_arkime "Usage: add_arkime_user <username> \"<Real Name>\" <password> [--admin]"
        return 1
    fi

    local username="$1"
    local realname="$2"
    local password="$3"
    local admin_flag=""
    if [ "$4" == "--admin" ]; then
        admin_flag="--admin"
    fi

    log_arkime "Attempting to add Arkime user: ${username}..."
    cd "${AXLAP_BASE_DIR}" || { log_arkime "ERROR: Failed to change directory to ${AXLAP_BASE_DIR}"; return 1; }

    # Ensure Arkime viewer container is running
    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" ps -q axlap-arkime-viewer 2>/dev/null | grep -q .; then
        log_arkime "ERROR: Arkime viewer container (axlap-arkime-viewer) is not running."
        return 1
    fi

    docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-arkime-viewer /opt/arkime/bin/arkime_add_user.sh "${username}" "${realname}" "${password}" ${admin_flag} >> "${LOG_FILE_ARKIME_CONFIG}" 2>&1
    if [ $? -eq 0 ]; then
        log_arkime "Successfully added Arkime user '${username}'."
    else
        log_arkime "ERROR: Failed to add Arkime user '${username}'. Check ${LOG_FILE_ARKIME_CONFIG} and docker logs for axlap-arkime-viewer."
        return 1
    fi
}

initialize_arkime_db() {
    log_arkime "Attempting to initialize Arkime database..."
    cd "${AXLAP_BASE_DIR}" || { log_arkime "ERROR: Failed to change directory to ${AXLAP_BASE_DIR}"; return 1; }

    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" ps -q axlap-arkime-viewer 2>/dev/null | grep -q .; then
        log_arkime "ERROR: Arkime viewer container (axlap-arkime-viewer) is not running."
        return 1
    fi
    if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" ps -q axlap-elasticsearch 2>/dev/null | grep -q .; then
        log_arkime "ERROR: Elasticsearch container (axlap-elasticsearch) is not running."
        return 1
    fi

    log_arkime "Waiting up to 30s for Elasticsearch to be ready for Arkime DB init..."
    # A simple sleep might be sufficient if ES was just started. A loop with curl check is more robust.
    # For now, using the one from install.sh as a reference.
    local count=0
    local max_wait=30 # seconds
    while ! docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-elasticsearch curl -s --fail http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s > /dev/null 2>&1; do
        sleep 5
        count=$((count + 5))
        if [ "${count}" -ge "${max_wait}" ]; then
            log_arkime "ERROR: Elasticsearch did not become ready in time for Arkime DB init."
            return 1
        fi
        printf "."
    done
    echo ""
    log_arkime "Elasticsearch is ready."

    if docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-arkime-viewer test -f /opt/arkime/db/db.pl; then
        echo "INIT" | docker-compose -f "${DOCKER_COMPOSE_FILE}" exec -T axlap-arkime-viewer /opt/arkime/db/db.pl http://axlap-elasticsearch:9200 init >> "${LOG_FILE_ARKIME_CONFIG}" 2>&1
        if [ $? -eq 0 ]; then
            log_arkime "Arkime database initialization command completed successfully."
        else
            log_arkime "WARNING: Arkime database initialization command failed or had non-zero exit. Check ${LOG_FILE_ARKIME_CONFIG}. It might have been initialized already."
        fi
    else
        log_arkime "ERROR: Arkime db.pl script not found in axlap-arkime-viewer container."
        return 1
    fi
}

# Main script logic
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 <command> [args]"
    echo "Commands:"
    echo "  initdb          - Initializes the Arkime database (use with caution if already initialized)."
    echo "  adduser <user> \"<Real Name>\" <pass> [--admin] - Adds a new Arkime user."
    exit 1
fi

COMMAND="$1"
shift

log_arkime "Arkime configuration script started with command: ${COMMAND}."

case "${COMMAND}" in
    initdb)
        initialize_arkime_db
        ;;
    adduser)
        add_arkime_user "$@"
        ;;
    *)
        log_arkime "ERROR: Unknown command '${COMMAND}'."
        echo "Unknown command: ${COMMAND}" >&2
        exit 1
        ;;
esac

log_arkime "Arkime configuration script finished."