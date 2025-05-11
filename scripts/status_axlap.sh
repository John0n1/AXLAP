#!/bin/bash
# Checks status of AXLAP services

# SCRIPT_DIR is defined in axlap_common_env.sh if sourced, otherwise set it here
if [ -z "${SCRIPT_DIR_COMMON}" ]; then
    CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
else
    CURRENT_SCRIPT_DIR="${SCRIPT_DIR_COMMON}"
fi
# shellcheck source=./axlap_common_env.sh
source "${CURRENT_SCRIPT_DIR}/axlap_common_env.sh"

# No separate log file for status script, output to console is primary.

echo "AXLAP Service Status (using Docker Compose):"
cd "${AXLAP_BASE_DIR}" || { echo "ERROR: Failed to change directory to ${AXLAP_BASE_DIR}." >&2; exit 1; }

if [ ! -f "${DOCKER_COMPOSE_FILE}" ]; then
    echo "ERROR: Docker Compose file ${DOCKER_COMPOSE_FILE} not found." >&2
    exit 1
fi

docker-compose -f "${DOCKER_COMPOSE_FILE}" ps

if [ $? -ne 0 ]; then
  echo "Error: Could not retrieve service status via Docker Compose. Is Docker running?"
  # exit 1 # Don't exit, still show endpoints
fi

echo ""
echo "Key Endpoints (availability depends on service status):"
echo "  AXLAP TUI:      Run 'cd ${AXLAP_BASE_DIR} && source venv/bin/activate && python3 src/tui/axlap_tui.py'"
# Check if OPENCTI_ADMIN_EMAIL is set to provide a more complete OpenCTI login hint
OPENCTI_LOGIN_HINT="(Login with credentials from .env or install log)"
if [ -n "${OPENCTI_ADMIN_EMAIL}" ]; then # OPENCTI_ADMIN_EMAIL is from sourced .env
    OPENCTI_LOGIN_HINT="(Login: ${OPENCTI_ADMIN_EMAIL} / <password_from_install>)"
fi
echo "  Arkime UI:      http://127.0.0.1:8005 (Login: admin / <password_from_install>)"
echo "  OpenCTI UI:     http://127.0.0.1:8080 ${OPENCTI_LOGIN_HINT}"
echo "  Elasticsearch:  http://127.0.0.1:9200"
if docker-compose -f "${DOCKER_COMPOSE_FILE}" ps -q axlap-opencti-s3 2>/dev/null | grep -q .; then
    MINIO_CONSOLE_USER_HINT="(Login with credentials from .env or install log)"
    if [ -n "${MINIO_ROOT_USER}" ]; then # MINIO_ROOT_USER from .env
        MINIO_CONSOLE_USER_HINT="(Login: ${MINIO_ROOT_USER} / <password_from_install>)"
    fi
    echo "  MinIO Console:  http://127.0.0.1:9001 ${MINIO_CONSOLE_USER_HINT}"
fi

echo ""
echo "To view logs for a specific service, e.g., Zeek:"
echo "  cd ${AXLAP_BASE_DIR} && docker-compose -f "${DOCKER_COMPOSE_FILE}" logs -f axlap-zeek"