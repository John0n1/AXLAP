#!/bin/bash
# Triggers ML model training within the ml_engine container.

# SCRIPT_DIR is defined in axlap_common_env.sh if sourced, otherwise set it here
if [ -z "${SCRIPT_DIR_COMMON}" ]; then
    CURRENT_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
else
    CURRENT_SCRIPT_DIR="${SCRIPT_DIR_COMMON}"
fi
# shellcheck source=./axlap_common_env.sh
source "${CURRENT_SCRIPT_DIR}/axlap_common_env.sh"

LOG_FILE_ML_TRAIN="${LOG_DIR}/ml_train.log"

log_ml_train() {
    _log_message_common "$1" # Will also log to ml_train.log if LOG_DIR is set
}

log_ml_train "Starting ML model training process..."
cd "${AXLAP_BASE_DIR}" || { log_ml_train "ERROR: Failed to change directory to ${AXLAP_BASE_DIR}. Training aborted."; exit 1; }

if [ ! -f "${DOCKER_COMPOSE_FILE}" ]; then
    log_ml_train "ERROR: Docker Compose file ${DOCKER_COMPOSE_FILE} not found. Training aborted."
    exit 1
fi

# Ensure the ml_engine service is defined in docker-compose
if ! docker-compose -f "${DOCKER_COMPOSE_FILE}" config --services | grep -q "ml_engine"; then
    log_ml_train "ERROR: 'ml_engine' service not found in ${DOCKER_COMPOSE_FILE}. Training aborted."
    exit 1
fi

# Ensure the training script path inside the container is correct
TRAIN_SCRIPT_PATH_IN_CONTAINER="ml_engine/train.py" # Relative to /app in ml_engine container

log_ml_train "Executing training script (python ${TRAIN_SCRIPT_PATH_IN_CONTAINER}) in ml_engine container..."
# The `run --rm` command starts a new container, runs the command, and then removes the container.
# Environment variables for the ml_engine service (like ELASTICSEARCH_HOST) are defined in docker-compose.yml.
docker-compose -f "${DOCKER_COMPOSE_FILE}" run --rm ml_engine python "${TRAIN_SCRIPT_PATH_IN_CONTAINER}" >> "${LOG_FILE_ML_TRAIN}" 2>&1

TRAIN_EXIT_CODE=$?

if [ ${TRAIN_EXIT_CODE} -eq 0 ]; then
  log_ml_train "ML model training script completed successfully."
  echo "ML model training script completed successfully. See ${LOG_FILE_ML_TRAIN} for details."
else
  log_ml_train "ERROR: ML model training script failed with exit code ${TRAIN_EXIT_CODE}. Check ${LOG_FILE_ML_TRAIN} for details."
  echo "ERROR: ML model training script failed. Check ${LOG_FILE_ML_TRAIN} for details." >&2
  exit 1
fi

log_ml_train "ML model training process finished."