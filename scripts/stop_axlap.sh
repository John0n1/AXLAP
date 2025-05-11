#!/bin/bash
# Stops AXLAP services and optionally removes volumes.

# SCRIPT_DIR is defined in axlap_common_env.sh if sourced, otherwise set it here
if [ -z "${SCRIPT_DIR_COMMON}" ]; then
    CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
else
    CURRENT_SCRIPT_DIR="${SCRIPT_DIR_COMMON}"
fi
# shellcheck source=./axlap_common_env.sh
source "${CURRENT_SCRIPT_DIR}/axlap_common_env.sh"

LOG_FILE_STOP="${LOG_DIR}/stop_axlap.log"

log_stop() {
    _log_message_common "$1"
}

REMOVE_VOLUMES=false
REMOVE_ORPHANS=true # Default to removing orphans

print_usage() {
    echo "Usage: $0 [--remove-volumes] [--keep-orphans]"
    echo "  --remove-volumes: Stop services and remove Docker volumes (WARNING: DATA LOSS)."
    echo "  --keep-orphans: Do not remove orphaned containers (if any)."
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --remove-volumes)
            REMOVE_VOLUMES=true
            shift # past argument
            ;;
        --keep-orphans)
            REMOVE_ORPHANS=false
            shift # past argument
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

cd "${AXLAP_BASE_DIR}" || { log_stop "ERROR: Failed to change directory to ${AXLAP_BASE_DIR}. Stop aborted."; exit 1; }

if [ ! -f "${DOCKER_COMPOSE_FILE}" ]; then
    log_stop "ERROR: Docker Compose file ${DOCKER_COMPOSE_FILE} not found."
    exit 1
fi

DOWN_OPTIONS=""
if [ "${REMOVE_VOLUMES}" = true ]; then
    log_stop "Stopping AXLAP services and REMOVING associated Docker volumes..."
    echo "WARNING: This will remove all Docker volumes associated with AXLAP services (e.g., Elasticsearch data, OpenCTI database)." >&2
    read -p "Are you sure you want to remove volumes? (yes/NO): " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        log_stop "Volume removal cancelled by user. Stopping services without removing volumes."
        DOWN_OPTIONS=""
    else
        log_stop "Proceeding with volume removal."
        DOWN_OPTIONS+=" -v"
    fi
else
    log_stop "Stopping AXLAP services..."
fi

if [ "${REMOVE_ORPHANS}" = true ]; then
    DOWN_OPTIONS+=" --remove-orphans"
else
    log_stop "Orphaned containers will not