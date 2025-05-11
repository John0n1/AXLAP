#!/bin/bash
# Common environment variables for AXLAP scripts and potentially for systemd EnvironmentFile

# Determine AXLAP_BASE_DIR dynamically if not already set
if [ -z "${AXLAP_BASE_DIR}" ]; then
  # If script is in /opt/axlap/scripts, then AXLAP_BASE_DIR is /opt/axlap
  # Otherwise, assume it's one level up from the script's directory's parent (e.g. if script is in ./scripts)
  SCRIPT_DIR_COMMON="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
  if [[ "${SCRIPT_DIR_COMMON}" == *"/scripts"* ]]; then
    export AXLAP_BASE_DIR="$(dirname "${SCRIPT_DIR_COMMON}")"
  else # Fallback or if script is run from an unexpected location
    export AXLAP_BASE_DIR="/opt/axlap" # Default if cannot determine
  fi
fi

export DOCKER_COMPOSE_FILE="${AXLAP_BASE_DIR}/docker-compose.yml"
export LOG_DIR="${AXLAP_BASE_DIR}/logs"

# Source the .env file from AXLAP_BASE_DIR to load project-specific environment variables
# This makes variables like OPENCTI_ADMIN_TOKEN, etc., available to scripts that source this file.
ENV_FILE_COMMON="${AXLAP_BASE_DIR}/.env"
if [ -f "${ENV_FILE_COMMON}" ]; then
  # Export all variables from .env file, stripping comments and empty lines
  # Using a loop to handle variables with spaces or special characters more robustly than `export $(cat ...)`
  set -a # Automatically export all variables subsequently defined or modified
  # shellcheck source=/dev/null
  source "${ENV_FILE_COMMON}"
  set +a
else
  echo "[axlap_common_env.sh] WARNING: Environment file ${ENV_FILE_COMMON} not found." >&2
fi

# Ensure critical variables that might be needed by scripts have defaults if not in .env
# These are typically set by install.sh into .env, but good for standalone script execution.
export CAPTURE_INTERFACE="${CAPTURE_INTERFACE_FROM_ENV:-eth0}"
export OPENCTI_ADMIN_TOKEN="${OPENCTI_ADMIN_TOKEN}" # Should be loaded from .env

# Function to log messages consistently if scripts need it
_log_message_common() {
    local SCRIPT_NAME
    SCRIPT_NAME=$(basename "${0:-unknown_script}")
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME}] $1"
    if [ -d "${LOG_DIR}" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${SCRIPT_NAME}] $1" >> "${LOG_DIR}/${SCRIPT_NAME}.log"
    fi
}