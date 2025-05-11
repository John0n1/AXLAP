#!/bin/bash
# Starts AXLAP services using Docker Compose

# SCRIPT_DIR is defined in axlap_common_env.sh if sourced, otherwise set it here
if [ -z "${SCRIPT_DIR_COMMON}" ]; then
    CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
else
    CURRENT_SCRIPT_DIR="${SCRIPT_DIR_COMMON}"
fi
# shellcheck source=./axlap_common_env.sh
source "${CURRENT_SCRIPT_DIR}/axlap_common_env.sh"

LOG_FILE_START="${LOG_DIR}/start_axlap.log"

log_start() {
    _log_message_common "$1" # Use common log function, will also log to start_axlap.log if LOG_DIR is set
}

log_start "Attempting to start AXLAP services from ${DOCKER_COMPOSE_FILE}..."
cd "${AXLAP_BASE_DIR}" || { log_start "ERROR: Failed to change directory to ${AXLAP_BASE_DIR}. Startup aborted."; exit 1; }

# Ensure .env file exists, as docker-compose relies on it for many configurations
if [ ! -f "${ENV_FILE}" ]; then # ENV_FILE is from axlap_common_env.sh
    log_start "ERROR: Environment file ${ENV_FILE} not found. Cannot start services. Run install.sh first."
    exit 1
fi

# The .env file in the same directory as docker-compose.yml is loaded automatically.
# No need for --env-file unless it's located elsewhere.
docker-compose -f "${DOCKER_COMPOSE_FILE}" up -d

if [ $? -eq 0 ]; then
  log_start "AXLAP services started successfully or were already running."
  echo "AXLAP services started successfully or were already running."
  echo "Run 'cd ${AXLAP_BASE_DIR} && docker-compose ps' or '${AXLAP_BASE_DIR}/scripts/status_axlap.sh' to check status."
else
  log_start "ERROR: Failed to start AXLAP services. Check Docker and Docker Compose logs."
  echo "ERROR: Failed to start AXLAP services. Check logs in ${LOG_DIR} and Docker daemon/container logs." >&2
  exit 1
fi