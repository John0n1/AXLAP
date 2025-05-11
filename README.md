
# AXLAP - Autonomous XKeyscore-Like Analysis Platform

![AXLAP](https://github.com/user-attachments/assets/7058ab71-c115-4629-8a8b-5912af30dc40)

AXLAP is a self-contained Linux-native application designed to replicate XKeyscore-class surveillance capabilities using open-source tools. It provides a unified interface for full session capture, metadata analysis, protocol fingerprinting, real-time behavioral flagging, and threat intelligence correlation.

**Mission Objective:** Build a single self-contained Linux-native application that replicates seven XKeyscore-class surveillance capabilities using only open-source tools.

## Features

1.  **Full Session Capture:** Arkime captures full packet data (PCAP), indexed and browsable by session. Zeek provides complementary session metadata.
2.  **Metadata Retention & Query:** Zeek logs are stored in Elasticsearch, allowing rich metadata querying.
3.  **Protocol Fingerprinting:** Suricata and Zeek work in tandem to identify and classify network protocols.
4.  **Plugin-Based Parsing:** Extend parsing capabilities with custom Zeek scripts, manageable via the AXLAP interface.
5.  **Real-Time Behavioral Flagging:** Suricata IDS alerts combined with locally trained Machine Learning models identify anomalous network behavior in real-time.
6.  **Social Graphing:** OpenCTI integration allows visualization of threat actor relationships, campaigns, and indicators. (Visualized textually in TUI, with Graphviz export option).
7.  **Cross-Database Federation:** OpenCTI acts as a central hub, integrating with MISP and other threat intelligence sources.

## Architecture Overview

AXLAP utilizes a containerized microservice architecture orchestrated by Docker Compose.

*   **Capture Layer:**
    *   **Zeek:** Network sensor providing deep packet inspection, protocol analysis, and rich metadata logs (JSON).
    *   **Suricata:** Intrusion Detection System (IDS) for signature-based threat detection, protocol identification, and rule-based alerting. Generates EVE JSON alerts.
    *   **Arkime (Capture & Viewer):** Provides full packet capture storage and a session-based browser. PCAPs are stored locally.
*   **Data Transport:**
    *   **Filebeat:** Ships logs from Zeek and Suricata to Elasticsearch.
*   **Storage & Indexing:**
    *   **Elasticsearch (Main):** Stores Zeek logs, Suricata alerts, and ML-generated alerts. Provides powerful search and aggregation capabilities.
    *   **Elasticsearch (OpenCTI):** Dedicated Elasticsearch instance for OpenCTI's backend.
*   **Analysis & Intelligence:**
    *   **AXLAP ML Engine:** Python-based machine learning component that trains on local network data (Zeek/Suricata logs) to detect behavioral anomalies.
    *   **OpenCTI:** Threat intelligence platform for organizing, storing, and correlating CTI data. Integrates with MISP.
    *   **MISP (via OpenCTI Connector):** Facilitates sharing and consumption of threat indicators. (AXLAP does not install MISP itself, but provides the OpenCTI connector for it).
*   **Presentation Layer:**
    *   **AXLAP TUI (Text User Interface):** A single, curses-based interface providing access to all AXLAP capabilities. Runs on the host system.
    *   **Web Interfaces:** Arkime and OpenCTI also have web interfaces for more detailed analysis and management.
## System Requirements

*   **Target OS:** Ubuntu 20.04/22.04 LTS (recommended). BackBox Linux may also work but is less tested.
*   **Hardware:**
    *   Multi-core CPU (4+ cores recommended).
    *   RAM: 16GB minimum, 32GB+ recommended for production use (Elasticsearch, Zeek, Arkime are memory intensive).
    *   Storage: Sufficient disk space for PCAPs and Elasticsearch indices (1TB+ recommended, depends on traffic volume). Fast SSDs are highly recommended.
*   **Software Prerequisites:** `git`, `curl`, `docker.io`, `docker-compose`, `python3`, `python3-pip`, `python3-venv`. The `install.sh` script will attempt to install these.
*   **Network:**
    *   A dedicated network interface for traffic capture (promiscuous mode required).
    *   Internet access for installation (downloading packages, Docker images, initial rulesets) and for optional threat feed updates. Post-install, core functionality is offline.

## Installation

**WARNING:** This system captures and analyzes network traffic. Ensure you have proper authorization and comply with all applicable laws and policies before deploying AXLAP. This tool is provided for educational and research purposes only.

1.  **Clone the Repository (or download and extract):**
    ```bash
    git clone https://github.com/John0n1/axlap.git 
    cd axlap
    ```

2.  **Review Configuration (Optional but Recommended):**
    *   Inspect `install.sh` to understand environment variables like `CAPTURE_INTERFACE` and `HOME_NETS`. You can set these variables in your shell before running the script to override defaults.
    *   Example: `export AXLAP_CAPTURE_INTERFACE=enp0s8`
    *   `export AXLAP_HOME_NETS="192.168.1.0/24,10.0.0.0/8"`
    *   Review `docker-compose.yml` and configuration files in `config/` if you need to make advanced changes.

3.  **Run the Installation Script:**
    The script must be run as root or with sudo.
    ```bash
    sudo ./install.sh
    ```
    This script will:
    *   Install system dependencies.
    *   Set up directories and permissions in `/opt/axlap`.
    *   Configure all services (Zeek, Suricata, Elasticsearch, Arkime, OpenCTI, etc.).
    *   Build custom Docker images and pull official ones.
    *   Initialize databases and download initial rulesets.
    *   Set up systemd services for auto-start and updates.
    *   Apply basic security hardening.

    Installation can take a significant amount of time depending on your internet connection and system performance. Monitor the output and the log file at `/opt/axlap/logs/install.log`.

## Usage

### Starting and Stopping AXLAP

AXLAP is managed by systemd services:

*   **Start AXLAP:** `sudo systemctl start axlap.service`
*   **Stop AXLAP:** `sudo systemctl stop axlap.service`
*   **Check Status:** `sudo systemctl status axlap.service`
*   **Enable on Boot (done by installer):** `sudo systemctl enable axlap.service`
*   **Disable on Boot:** `sudo systemctl disable axlap.service`

You can also use the helper scripts in `/opt/axlap/scripts/`:
*   `sudo /opt/axlap/scripts/start_axlap.sh`
*   `sudo /opt/axlap/scripts/stop_axlap.sh`
*   `sudo /opt/axlap/scripts/status_axlap.sh`

### Accessing the AXLAP TUI

The primary interface to AXLAP is the Text User Interface (TUI).

1.  **Activate Python Virtual Environment (optional but recommended for direct script execution):**
    ```bash
    cd /opt/axlap
    source venv/bin/activate
    ```
2.  **Run the TUI:**
    ```bash
    # If venv is activated:
    python3 src/tui/axlap_tui.py
    # Or directly:
    # /opt/axlap/venv/bin/python3 /opt/axlap/src/tui/axlap_tui.py
    ```
    For convenience, you might want to create an alias or a small wrapper script in `/usr/local/bin`.

    **TUI Navigation:**
    *   Use keyboard shortcuts displayed in the header/footer or press `H` (or `F1`) for help.
    *   Common shortcuts: `D` (Dashboard), `Q` (Query), `S` (Sessions), `P` (Plugins), `G` (Graph), `ESC` or `q` (Quit).

### Web Interfaces (for detailed views or administration)

While the TUI is the primary single interface, some underlying components also have web UIs accessible locally:

*   **Arkime Viewer:** `http://127.0.0.1:8005`
    *   Provides advanced session exploration, PCAP download, and visualization.
    *   Default credentials (set during install, **CHANGE THESE!**): `admin` / `AdminAXLAPPassw0rd` (or similar generated password, check install log).
*   **OpenCTI Platform:** `http://127.0.0.1:8080`
    *   Manage threat intelligence, connectors, users, and explore graph data in more detail.
    *   Admin credentials set during install (e.g., `admin@axlap.local` / `ChangeMeAXLAP!...`). Check `install.sh` output, `/opt/axlap/logs/install.log`, or the generated values in `/opt/axlap/docker-compose.yml` for exact values. **CHANGE THESE!**
*   **Elasticsearch (API):**
    *   Elasticsearch itself is accessible at `http://127.0.0.1:9200`.
    *   You can install Kibana separately and point it to this Elasticsearch instance for advanced data visualization and dashboarding if needed. AXLAP does not install Kibana by default to keep the system lean.

### Key Features in TUI

*   **Dashboard:** Overview of recent alerts (Suricata, ML), Zeek log activity.
*   **Query Panel:** Execute Lucene queries against Elasticsearch indices (Zeek logs, Suricata alerts, ML alerts).
*   **Session Browser:** Search and list network sessions from Arkime. View basic session details. Option to extract PCAP segment (e.g., using `tshark` locally - `tshark` needs to be installed separately) or provides information to find the session in Arkime Web UI for full PCAP.
*   **Protocol/Event Drill-down:** (Integrated into Query/Session views) Show detailed information for selected events.
*   **Plugin Manager:** View available Zeek scripts in `/opt/axlap/src/zeek_plugins/`. Enable/disable plugins by managing their configuration (YAML/JSON files in `/opt/axlap/config/zeek/plugin_configs/`) which then influences Zeek's `local.zeek` or a dynamic loader script.
*   **Correlation Graph Visualizer:** Query OpenCTI for entities (IPs, domains, malware) and display their relationships in a text-based format. Option to export data for Graphviz (`.dot` file).
*   **Alert Dashboard:** Real-time (periodic refresh) display of flags from Suricata and the ML engine.

## Machine Learning

*   **Local Training:** ML models are trained locally using data from Zeek `conn.log` (initially) and potentially Suricata alerts in the future. No cloud dependencies.
*   **Anomaly Detection:** The initial model is an Isolation Forest for detecting anomalous network connections based on features like duration, byte counts, packet counts, protocol, etc.
*   **Training Data:** Historical logs stored in Elasticsearch are used.
*   **Triggering Training:**
    *   Via the TUI (Option available in a management/ML view - to be fully implemented).
    *   Manually: `sudo /opt/axlap/scripts/train_ml_model.sh` (This executes `docker-compose run --rm ml_engine ...`)
*   **Prediction:** A script (`src/ml_engine/predict.py`) runs periodically (via systemd timer `axlap-ml-predict.timer`) to score new data and write alerts to the `axlap-ml-alerts-*` Elasticsearch index.

## Updates

*   **Rulesets and Threat Feeds:** Updated automatically by a systemd timer (`axlap-updates.timer`) which runs `scripts/update_rules_and_feeds.sh` daily.
    *   **Suricata Rules:** Uses `suricata-update`.
    *   **OpenCTI Feeds:** Relies on configured polling intervals of OpenCTI connectors (e.g., MISP connector). The update script primarily focuses on Suricata rules and local Zeek intel.
*   **Manual Update Trigger:** `sudo /opt/axlap/scripts/update_rules_and_feeds.sh`

## Security

*   **Secure by Default (Best Effort for a Self-Contained System):**
    *   Services are containerized with Docker, providing a degree of isolation.
    *   `iptables` rules are applied by the installer for basic host protection (focused on loopback and established connections). Docker manages its own rules for container networking. You should review and adapt these based on your environment and security policies.
    *   AppArmor: The system is AppArmor-aware. The installer enables AppArmor if available. Custom AppArmor profiles for each container can be developed and placed in `/opt/axlap/apparmor/` (directory not created by default) and loaded. This requires manual profile creation specific to the workload of each container.
    *   Exposed service ports (Elasticsearch, Arkime UI, OpenCTI UI) are bound to `127.0.0.1` by default in `docker-compose.yml`, limiting direct external access. If external access is needed, consider using a reverse proxy with proper authentication and TLS.
    *   **Secrets Management:** Passwords and API keys are generated during installation or taken from environment variables. These are stored in configuration files (`docker-compose.yml`, `axlap_tui_config.ini`, etc.) within `/opt/axlap`. Access to `/opt/axlap` should be restricted. **IT IS CRUCIAL TO CHANGE DEFAULT GENERATED PASSWORDS** for Arkime and OpenCTI immediately after installation via their respective web UIs.
    *   **No Internet Dependency Post-Install (Core Functionality):** After initial setup and rule/feed download, AXLAP's core analysis capabilities can operate in an air-gapped environment. Updates for rules and threat intelligence feeds will require internet connectivity.
    *   **Sandboxing of TUI:** The TUI itself runs as a Python application on the host. Consider running it under `firejail` or a similar sandboxing tool for added protection if desired, though this is not configured by default.

## Troubleshooting

*   **Installation Issues:** Check `/opt/axlap/logs/install.log` for detailed error messages. Ensure all prerequisites are met and that you have a stable internet connection during installation.
*   **Service Failures:**
    *   Use `sudo systemctl status axlap.service` to check the main service.
    *   Use `cd /opt/axlap && sudo docker-compose ps` to see the status of individual containers.
    *   Check container logs: `cd /opt/axlap && sudo docker-compose logs <service_name>` (e.g., `axlap-zeek`, `axlap-elasticsearch`).
*   **Elasticsearch Issues:**
    *   Elasticsearch is memory-intensive. Ensure sufficient RAM is allocated to the Docker daemon and that the host has enough free memory. `ES_JAVA_OPTS` in `docker-compose.yml` can be adjusted.
    *   Check Elasticsearch logs: `sudo docker-compose logs axlap-elasticsearch`.
    *   Common issues: disk space full, incorrect permissions on data directories (Docker volumes usually handle this), cluster health (yellow is okay for single node, red indicates problems).
*   **Zeek/Suricata Not Capturing Traffic:**
    *   Verify `CAPTURE_INTERFACE` is correctly set during installation and in container configurations.
    *   Ensure the interface is in promiscuous mode: `ip link show ${CAPTURE_INTERFACE}` should show `PROMISC`. If not, `sudo ip link set ${CAPTURE_INTERFACE} promisc on`.
    *   Ensure traffic is actually reaching the interface (use `tcpdump` on the host). If AXLAP is on a VM, ensure the VM's network is configured for promiscuous mode or that a TAP/SPAN port is correctly directing traffic to it.
    *   Check Zeek logs: `/opt/axlap/data/zeek_logs_raw/` and container logs for `axlap-zeek`.
    *   Check Suricata logs: `/opt/axlap/data/suricata_logs/` and container logs for `axlap-suricata`.
*   **TUI Errors:**
    *   Check `/tmp/axlap_tui_error.log` (or similar path if configured differently) for Python tracebacks from the TUI.
    *   Ensure Elasticsearch, Arkime, and OpenCTI services are running and accessible from the host on `127.0.0.1` at their respective ports.

## Extensibility

*   **Zeek Plugins:** Add custom Zeek scripts (`.zeek` files) to `/opt/axlap/src/zeek_plugins/`. Create corresponding YAML configuration files in `/opt/axlap/config/zeek/plugin_configs/` to describe them and allow management via the TUI. Modify `/opt/axlap/config/zeek/site/local.zeek` to load new plugins.
*   **Suricata Rules:** Add custom Suricata rules to `/opt/axlap/rules/local.rules`. These are automatically loaded by Suricata.
*   **ML Models:** The ML engine is designed to be modular. You can add new models or feature engineering techniques by modifying files in `/opt/axlap/src/ml_engine/`.
*   **OpenCTI Connectors:** Deploy additional OpenCTI connectors (as Docker containers, add to `docker-compose.yml`) to integrate with more threat intelligence sources.
*   **TUI Views:** Add new views to the TUI by creating new Python classes in `/opt/axlap/src/tui/views/` and integrating them into `axlap_tui.py`.

## Future Work / Potential Enhancements

*   More sophisticated ML models (e.g., deep learning for DGA, encrypted traffic analysis).
*   Enhanced TUI visualizations (e.g., basic histograms, timelines).
*   Automated report generation.
*   Integration with endpoint detection and response (EDR) logs.
*   More comprehensive AppArmor/Firejail profiles.
*   Full Kibana integration for advanced dashboarding, pre-configured with AXLAP data.
*   Automated PCAP data lifecycle management (e.g., auto-deletion of old PCAPs).
*   Support for other capture interfaces/methods (e.g., PF_RING, DPDK, AF_XDP).
*   User and role management for AXLAP TUI itself.

## Disclaimer

AXLAP is a powerful network analysis tool. It is intended for educational, research, and authorized security monitoring purposes only. The user is solely responsible for ensuring that its use complies with all applicable local, state, national, and international laws, regulations, and ethical guidelines. The creators and contributors of AXLAP assume no liability and are not responsible for any misuse or damage caused by this program. Use at your own risk.

## License
**MIT**
This project is primarily composed of open-source components, each under its own license.
The AXLAP-specific code (installer, TUI, custom scripts, configurations) is provided under the [MIT License](LICENSE.md) unless otherwise stated. Please check the individual licenses of the bundled open-source tools (Zeek, Suricata, Elasticsearch, Arkime, OpenCTI, etc.) for their respective terms.
