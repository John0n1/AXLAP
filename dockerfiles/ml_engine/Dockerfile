FROM python:3.9-slim

WORKDIR /app

# Install system dependencies that might be needed by Python ML libraries
# Example: build-essential for C extensions, libgomp1 for some scikit-learn components
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    liblapack-dev \
    libblas-dev \
    gfortran \
    libgomp1 && \
    rm -rf /var/lib/apt/lists/*

# Copy only the requirements file first to leverage Docker cache
# Context is now project root, so path is relative to project root.
COPY src/ml_engine/requirements.txt /app/requirements.txt

# Install Python dependencies
# Using --no-cache-dir to reduce image size
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the ML engine source code
# Context is now project root.
COPY src/ml_engine /app/ml_engine

# Create directories for models and logs if scripts write to them directly within the container.
# These paths should align with volume mounts in docker-compose.yml for persistence.
RUN mkdir -p /app/ml_engine/models && \
    mkdir -p /app/logs

# Set default user to non-root if possible, though ML tasks might need specific permissions
# USER appuser

# No CMD or ENTRYPOINT by default, as this container is typically run for specific tasks
# (e.g., train, predict) via `docker-compose run`.
# If it were a long-running service (e.g., an API), a CMD would be appropriate.
