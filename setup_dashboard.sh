#!/bin/sh

# --- Configuration ---
APP_BASE_DIR="/www/em9190" # Thư mục cài đặt mới cho dashboard
APP_SOURCE_DIR="/root/em9190_files" # Thư mục nơi bạn đặt các tệp nguồn ứng dụng (trước khi setup)
EXISTING_3GINFO_SCRIPT="/usr/share/3ginfo-lite/3ginfo.sh" # Đường dẫn tới script 3ginfo.sh đã có sẵn trên hệ thống

PYTHON_CMD="/usr/bin/python3" # Lệnh python3 hệ thống
FLASK_APP_SCRIPT="app.py"
SERVICE_NAME="em9190_dashboard"
PORT=9999 # Port mà ứng dụng Flask chạy
INIT_SCRIPT_PATH="/etc/init.d/${SERVICE_NAME}"
PID_FILE="${APP_BASE_DIR}/${SERVICE_NAME}.pid"
VENV_DIR="${APP_BASE_DIR}/venv"
VENV_TARBALL="venv.tar.gz" # Tên file nén môi trường ảo nếu có
UHTTPD_PROXY_SECTION_NAME="em9190_proxy" # Tên section tùy ý cho proxy trong uhttpd

# --- Helper Functions ---
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warning() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >&2; return 1; } # Trả về mã lỗi và ghi ra stderr

# Function to check if a command exists
check_cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install package and check for success
install_pkg() {
    local pkg_name="$1"
    
    if check_cmd_exists "$pkg_name"; then
        log_info "[INFO] Package '$pkg_name' is already installed."
        return 0
    fi
    
    log_info "[INFO] Package '$pkg_name' not found. Attempting to install..."
    if ! opkg update; then
        log_error "[ERROR] Failed to update opkg. Please check internet connection."
        return 1
    fi
    if ! opkg install "$pkg_name"; then
        log_error "[ERROR] Failed to install '$pkg_name'. Please install it manually using 'opkg install $pkg_name'."
        return 1
    fi
    log_info "[INFO] Package '$pkg_name' installed successfully."
    return 0
}

# Function to clean up partial setup
cleanup_failed_setup() {
    log_warning "An error occurred during setup. Attempting to clean up partially installed files..."
    
    # Stop the service if it's running
    if [ -f "${PID_FILE}" ]; then
        log_warning "Stopping any running instance of ${SERVICE_NAME}..."
        start-stop-daemon -K -p "${PID_FILE}" --quiet || true 
        rm -f "${PID_FILE}"
    fi
    
    # Remove the init.d script
    [ -f "${INIT_SCRIPT_PATH}" ] && rm "${INIT_SCRIPT_PATH}"
    # Remove the service symlink if it exists
    [ -L "/etc/rc.d/S90${SERVICE_NAME}" ] && rm "/etc/rc.d/S90${SERVICE_NAME}"

    # Removing uhttpd config is risky if partial, so we'll leave a warning instead.
    log_warning "Cleanup attempted for service files. If uhttpd configuration was partially applied, please review and clean it manually."
}

# --- Script Execution ---

# Trap errors to perform cleanup
trap 'cleanup_failed_setup; exit 1' ERR

log_info "--- Starting EM9190 Dashboard Setup ---"

# 1. Kiểm tra và cài đặt các gói cần thiết
log_info "Step 1: Checking and installing necessary packages..."
if ! install_pkg python3; then exit 1; fi
if ! install_pkg python3-pip; then exit 1; fi
# Cài đặt gói python3-flask của hệ thống là tùy chọn, vì ta dùng venv. Tuy nhiên, nó hữu ích nếu Flask được dùng chung.
if ! install_pkg python3-flask; then log_warning "[WARN] System package python3-flask not found. Relying on pip install in venv."; fi 
if ! install_pkg comgt; then log_warning "[WARN] comgt package not installed. sms_tool might not work correctly."; fi
if ! install_pkg screen; then log_warning "[WARN] screen package not installed. Useful for process management."; fi

# Check for start-stop-daemon (critical for service management on OpenWrt)
if ! check_cmd_exists "start-stop-daemon"; then
    log_error "Critical command 'start-stop-daemon' not found. This is essential for managing services on OpenWrt. Ensure initscripts package is installed."
    exit 1
fi
log_info "[INFO] Critical command 'start-stop-daemon' found."

# 2. Kiểm tra sự tồn tại của các script đã có sẵn
log_info "Step 2: Verifying existence of existing scripts..."
if ! [ -x "${EXISTING_3GINFO_SCRIPT}" ]; then
    log_error "Script '${EXISTING_3GINFO_SCRIPT}' not found or not executable. Please ensure '3ginfo-lite' package is installed correctly."
    exit 1
fi
log_info "[INFO] Found and executable script: ${EXISTING_3GINFO_SCRIPT}"

# --- MANUAL STEP REQUIRED ---
log_warning "--------------------------------------------------------------------"
log_warning "ACTION REQUIRED:"
log_warning "Please copy the following files/directories from your local machine"
log_warning "to '${APP_SOURCE_DIR}' ON THE ROUTER:"
log_warning "  - app.py"
log_warning "  - requirements.txt"
log_warning "  - static/ (directory containing css/ and js/)"
log_warning "  - templates/ (directory containing index.html)"
log_warning "  - ${VENV_TARBALL} (if you have a pre-built venv for your router's architecture)"
log_warning "--------------------------------------------------------------------"
read -p "Press Enter after copying the files to '${APP_SOURCE_DIR}'..."

# --- Kiểm tra sự tồn tại của các tệp ứng dụng MỚI SAU KHI sao chép ---
log_info "Step 3: Verifying required application files after copy..."
if ! [ -f "${APP_SOURCE_DIR}/app.py" ]; then log_error "app.py not found in ${APP_SOURCE_DIR}. Setup failed."; exit 1; fi
if ! [ -f "${APP_SOURCE_DIR}/requirements.txt" ]; then log_error "requirements.txt not found in ${APP_SOURCE_DIR}. Setup failed."; exit 1; fi
if ! [ -d "${APP_SOURCE_DIR}/static" ]; then log_error "static/ directory not found in ${APP_SOURCE_DIR}. Setup failed."; exit 1; fi
if ! [ -d "${APP_SOURCE_DIR}/templates" ]; then log_error "templates/ directory not found in ${APP_SOURCE_DIR}. Setup failed."; exit 1; fi
log_info "[INFO] Required application files verified."

# 4. Tạo cấu trúc thư mục ứng dụng mới và sao chép tệp
log_info "Step 4: Setting up application directory structure and copying files..."
mkdir -p "${APP_BASE_DIR}/static"
mkdir -p "${APP_BASE_DIR}/templates"
mkdir -p "${APP_BASE_DIR}/venv" # Create venv directory even if tarball exists

# Sao chép các tệp ứng dụng mới vào vị trí cài đặt cuối cùng
log_info "[INFO] Copying application files to ${APP_BASE_DIR}..."
cp "${APP_SOURCE_DIR}/app.py" "${APP_BASE_DIR}/" || { log_error "Failed to copy app.py."; exit 1; }
cp "${APP_SOURCE_DIR}/requirements.txt" "${APP_BASE_DIR}/" || { log_error "Failed to copy requirements.txt."; exit 1; }
cp -r "${APP_SOURCE_DIR}/static" "${APP_BASE_DIR}/" || { log_error "Failed to copy static directory."; exit 1; }
cp -r "${APP_SOURCE_DIR}/templates" "${APP_BASE_DIR}/" || { log_error "Failed to copy templates directory."; exit 1; }

# Xử lý môi trường ảo (tạo mới hoặc giải nén)
VENV_PYTHON_EXEC="${APP_BASE_DIR}/venv/bin/python"
VENV_PIP_EXEC="${APP_BASE_DIR}/venv/bin/pip"

if [ -f "${APP_SOURCE_DIR}/${VENV_TARBALL}" ]; then
    log_info "[INFO] Extracting virtual environment from ${APP_SOURCE_DIR}/${VENV_TARBALL} to ${APP_BASE_DIR}/venv/..."
    # Ensure venv directory is clean before extraction
    if ! rm -rf "${APP_BASE_DIR}/venv/*"; then
        log_warning "[WARN] Could not clear existing ${APP_BASE_DIR}/venv. Proceeding with extraction."
    fi
    tar -xzf "${APP_SOURCE_DIR}/${VENV_TARBALL}" -C "${APP_BASE_DIR}/venv/" || { log_error "Failed to extract virtual environment from ${VENV_TARBALL}."; exit 1; }
    log_info "[INFO] Virtual environment extracted."
else
    log_info "[INFO] No ${VENV_TARBALL} found. Creating new Python virtual environment at ${APP_BASE_DIR}/venv/..."
    # Remove existing venv contents if it exists but is not from tarball
    if [ -d "${APP_BASE_DIR}/venv" ] && [ "$(ls -A ${APP_BASE_DIR}/venv)" ]; then
        log_warning "[WARN] Existing content found in ${APP_BASE_DIR}/venv. Clearing it."
        rm -rf "${APP_BASE_DIR}/venv/*"
    fi
    
    "${PYTHON_CMD}" -m venv "${APP_BASE_DIR}/venv" || { log_error "Failed to create virtual environment at ${APP_BASE_DIR}/venv."; exit 1; }
    log_info "[INFO] New virtual environment created."
fi

# Verify python executable in venv exists
if ! [ -x "${VENV_PYTHON_EXEC}" ]; then
    log_error "Python executable in virtual environment (${VENV_PYTHON_EXEC}) not found. Setup failed."
    exit 1
fi
log_info "[INFO] Virtual environment Python executable found: ${VENV_PYTHON_EXEC}"

# Cài đặt thư viện Python vào venv
log_info "[INFO] Installing Python dependencies from requirements.txt using venv's pip..."
if ! "${VENV_PIP_EXEC}" install -r "${APP_BASE_DIR}/requirements.txt"; then
    log_error "Failed to install Python dependencies. Please check requirements.txt and permissions."
    exit 1
fi
log_info "[INFO] Python dependencies installed successfully."

# 5. Cấp quyền thực thi cho script 3ginfo.sh
log_info "Step 5: Ensuring execute permissions for existing script: ${EXISTING_3GINFO_SCRIPT}..."
chmod +x "${EXISTING_3GINFO_SCRIPT}" || log_warning "[WARN] Failed to set execute permission for ${EXISTING_3GINFO_SCRIPT}."

# 6. Tạo init.d script cho dịch vụ dashboard
log_info "Step 6: Creating init.d script for the dashboard service..."

# Chuỗi lệnh để chạy Flask từ venv
FLASK_RUN_CMD="${VENV_PYTHON_EXEC} ${FLASK_APP_SCRIPT}" 

# Nội dung của file init.d script
INIT_SCRIPT_CONTENT=$(cat << EOF
#!/bin/sh /etc/rc.common

START=90
STOP=10
SERVICE_NAME="${SERVICE_NAME}"
APP_DIR="${APP_BASE_DIR}"
PYTHON_EXEC="${VENV_PYTHON_EXEC}" 
FLASK_APP_SCRIPT="${FLASK_APP_SCRIPT}"
PORT="${PORT}"
PID_FILE="${PID_FILE}"
# LOG_FILE="${APP_BASE_DIR}/nohup.out" # nohup.out sẽ không được dùng bởi start-stop-daemon nếu redirect stdout/stderr

start() {
    log_info "Starting \${SERVICE_NAME}..."
    [ -d "\${APP_DIR}" ] || { log_error "App directory \${APP_DIR} missing."; return 1; }
    [ -x "\${PYTHON_EXEC}" ] || { log_error "Python executable from venv not found at \${PYTHON_EXEC}. Cannot start service."; return 1; }
    [ -f "\${APP_DIR}/\${FLASK_APP_SCRIPT}" ] || { log_error "Flask app script (\${APP_DIR}/\${FLASK_APP_SCRIPT}) not found. Cannot start service."; return 1; }

    # Check if already running
    if [ -f "\${PID_FILE}" ]; then
        PID=\$(cat "\${PID_FILE}")
        if ps -p "\$PID" > /dev/null; then
            log_info "\${SERVICE_NAME} is already running (PID: \$PID)."
            return 0
        fi
        log_warning "Stale PID file found for \${SERVICE_NAME}. Removing it."
        rm -f "\${PID_FILE}"
    fi

    log_info "Starting \${SERVICE_NAME} using \${PYTHON_EXEC} on port \${PORT}."
    
    # start-stop-daemon will manage the process in the background, write PID, and handle signals.
    # --chdir: Crucial for Flask to find static/templates.
    # --exec: The actual executable.
    # Arguments after -- are passed to the executable.
    # We redirect stdout and stderr to /dev/null to avoid filling up syslog, or to a log file if preferred.
    # For simplicity, we'll let start-stop-daemon manage this. If you need logs, adjust accordingly.
    start-stop-daemon -S -b -p "\${PID_FILE}" -m -N "\${SERVICE_NAME}" -u root --chdir "\${APP_DIR}" --exec "\${PYTHON_EXEC}" -- "\${FLASK_APP_SCRIPT}" 
    
    if [ \$? -eq 0 ]; then
        log_info "\${SERVICE_NAME} started successfully (PID: \$(cat "\${PID_FILE}"))."
    else
        log_error "Failed to start \${SERVICE_NAME}. Check logs."
        [ -f "\${PID_FILE}" ] && rm "\${PID_FILE}" # Clean up PID file if start failed.
        return 1
    fi
}

stop() {
    log_info "Stopping ${SERVICE_NAME}..."
    if [ -f "${PID_FILE}" ]; then
        start-stop-daemon -K -p "${PID_FILE}" --quiet
        if [ \$? -eq 0 ]; then
            log_info "${SERVICE_NAME} stopped successfully."
            rm -f "${PID_FILE}"
        else
            log_error "Failed to stop ${SERVICE_NAME} (PID: \$(cat "${PID_FILE}")). It might not be running or PID is stale."
            # Attempt to remove stale PID file
            rm -f "${PID_FILE}"
            return 1
        fi
    else
        log_info "${SERVICE_NAME} is not running (no PID file found)."
    fi
    return 0
}

restart() {
    stop
    sleep 2 # Give some time for the process to fully terminate
    start
}

enable() {
    log_info "Enabling ${SERVICE_NAME} service to start on boot..."
    chmod +x "${INIT_SCRIPT_PATH}"
    local LINK="/etc/rc.d/S90${SERVICE_NAME}" # Use a consistent symlink name for startup
    if [ ! -L "\$LINK" ]; then
        ln -s "${INIT_SCRIPT_PATH}" "\$LINK"
        log_info "${SERVICE_NAME} enabled. It will start on boot."
    else
        log_info "${SERVICE_NAME} is already enabled."
    fi
}

disable() {
    log_info "Disabling ${SERVICE_NAME} service from starting on boot..."
    rm -f "/etc/rc.d/S90${SERVICE_NAME}"
    log_info "${SERVICE_NAME} disabled."
}

status() {
    if [ -f "${PID_FILE}" ]; then
        PID=\$(cat "${PID_FILE}")
        if ps -p "\$PID" > /dev/null; then
            echo "${SERVICE_NAME} is running (PID: \$PID)."
            return 0
        else
            echo "${SERVICE_NAME} is stopped (stale PID file found)."
            return 3
        fi
    else
        echo "${SERVICE_NAME} is stopped."
        return 3
    fi
}

case "\$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    enable)
        enable
        ;;
    disable)
        disable
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|enable|disable|status}"
        exit 1
        ;;
esac
EOF
)

echo "$INIT_SCRIPT_CONTENT" > "${INIT_SCRIPT_PATH}" || { log_error "Failed to write init.d script to ${INIT_SCRIPT_PATH}."; exit 1; }
chmod +x "${INIT_SCRIPT_PATH}" || { log_error "Failed to make init.d script executable."; exit 1; }
log_info("[INFO] init.d script created and made executable at ${INIT_SCRIPT_PATH}.")

# 7. Kích hoạt và Khởi động Dịch vụ
log_info("Step 7: Enabling and starting the ${SERVICE_NAME} service...")
if ! service "${SERVICE_NAME}" enable; then
    log_warning("[WARN] Failed to enable service. Check permissions for ${INIT_SCRIPT_PATH} and /etc/rc.d/.")
fi
if ! service "${SERVICE_NAME}" start; then
    log_error("Failed to start the service '${SERVICE_NAME}'. Check logs in ${APP_BASE_DIR}/nohup.out or system logs (/var/log/messages).")
    exit 1
fi
log_info("[INFO] Service '${SERVICE_NAME}' enabled and started.")

# 8. Cấu hình uhttpd để proxy requests đến Flask app
log_info("Step 8: Configuring uhttpd to proxy requests to Flask app on port ${PORT}...")

# Xóa cấu hình cũ nếu có để tránh trùng lặp
CONFIG_EXISTS=$(uci show uhttpd | grep -q "config uhttpd '${UHTTPD_PROXY_SECTION_NAME}'" && echo "yes" || echo "no")
if [ "$CONFIG_EXISTS" = "yes" ]; then
    log_warning("[WARN] uhttpd proxy section '${UHTTPD_PROXY_SECTION_NAME}' already exists. Deleting and recreating for consistency.")
    uci delete uhttpd.${UHTTPD_PROXY_SECTION_NAME}
fi

# Thêm cấu hình proxy mới
uci add uhttpd proxy
uci set uhttpd.@proxy[-1]=${UHTTPD_PROXY_SECTION_NAME} 
uci set uhttpd.@proxy[-1].forward_host="0.0.0.0" # Proxy đến localhost (Flask listening on all interfaces)
uci set uhttpd.@proxy[-1].forward_port="${PORT}"
# Proxy TẤT CẢ các yêu cầu đến Flask app. Flask sẽ tự xử lý các static files, templates.
uci add_list uhttpd.@proxy[-1].forward_rule="/* http" 

if ! uci commit uhttpd; then
    log_error("Failed to commit uhttpd configuration.")
    exit 1
fi
log_info("[INFO] uhttpd configuration added. Reloading uhttpd...")
if ! /etc/init.d/uhttpd reload; then
    log_error("Failed to reload uhttpd. Please restart it manually: /etc/init.d/uhttpd restart")
    # Continue execution even if uhttpd reload fails, as the service might still work if it was already running.
fi
log_info("[INFO] uhttpd configuration updated.")

# --- Final Success Message ---
log_info "-----------------------------------------------------------"
log_info " EM9190 Dashboard Setup Script Finished Successfully."
log_info " Your EM9190 Dashboard should be accessible at:"
log_info "   http://<YOUR_ROUTER_IP>:${PORT}"
log_info "   (Replace <YOUR_ROUTER_IP> with your router's actual IP address)"
log_info "-----------------------------------------------------------"
log_info "Troubleshooting Tips:"
log_info " - Check service status: service ${SERVICE_NAME} status"
log_info " - View logs: logread | grep ${SERVICE_NAME}"
log_info " - Verify Flask app directly (from ${APP_BASE_DIR}): ${VENV_PYTHON_EXEC} ${FLASK_APP_SCRIPT}"
log_info " - Check uhttpd config: uci show uhttpd"
log_info "-----------------------------------------------------------"

exit 0
