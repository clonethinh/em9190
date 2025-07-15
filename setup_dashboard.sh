#!/bin/sh

# --- Configuration ---
APP_BASE_DIR="/www/em9190" # Thư mục cài đặt mới cho dashboard
APP_SOURCE_DIR="/root/em9190_files" # Thư mục nơi bạn đặt các tệp nguồn mới (app.py, static, templates, requirements.txt, venv.tar.gz)
# Đường dẫn tới các script đã có sẵn trên hệ thống
EXISTING_3GINFO_SCRIPT="/root/usr/share/3ginfo-lite/3ginfo.sh"
# Chúng ta không cần sao chép 3ginfo.sh nữa, chỉ cần đảm bảo nó có quyền thực thi.
# Các script modem con (như 119990d3) sẽ được 3ginfo.sh gọi trực tiếp.

PYTHON_CMD="/usr/bin/python3"
FLASK_APP_SCRIPT="app.py"
SERVICE_NAME="em9190_dashboard"
UHTTPD_CONFIG="/etc/config/uhttpd"
PORT=9999 # Port mà ứng dụng Flask chạy
INIT_SCRIPT_PATH="/etc/init.d/${SERVICE_NAME}"
PID_FILE="${APP_BASE_DIR}/${SERVICE_NAME}.pid"
VENV_DIR="${APP_BASE_DIR}/venv"
VENV_TARBALL="venv.tar.gz" # Tên file nén môi trường ảo nếu có

# --- Helper Functions ---
log_info() { echo "[INFO] $1"; }
log_warning() { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; return 1; }

check_cmd_installed() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Command '$1' not found. Please install it using 'opkg install $1'."
        return 1
    fi
    return 0
}

cleanup_failed_setup() {
    log_warning "An error occurred. Attempting to clean up partially installed files..."
    if [ -f "$PID_FILE" ]; then
        log_warning "Stopping any running instance of ${SERVICE_NAME}..."
        start-stop-daemon -K -p "$PID_FILE" --quiet || true
        rm -f "$PID_FILE"
    fi
    [ -f "$INIT_SCRIPT_PATH" ] && rm "$INIT_SCRIPT_PATH"
    # Xóa cấu hình uhttpd phức tạp hơn, chỉ reload là đủ cho hầu hết trường hợp
    log_warning "Cleanup complete. Please review the logs and try again after fixing issues."
}

# --- Script Execution ---

log_info "--- Starting EM9190 Dashboard Setup ---"

# 1. Kiểm tra các gói cần thiết và cài đặt nếu thiếu
log_info "Checking and installing necessary packages..."
opkg update || log_error "Failed to update opkg. Please ensure you have internet connection."
check_cmd_installed "python3" || exit 1
check_cmd_installed "pip3" || log_error "pip3 not found. Attempting to install..." || opkg install python3-pip || exit 1
check_cmd_installed "python3-flask" || log_info "Flask not found, attempting to install..." || opkg install python3-flask
check_cmd_installed "comgt" || log_info "comgt not found, attempting to install..." || opkg install comgt
check_cmd_installed "screen" || log_info "screen not found, attempting to install..." || opkg install screen
check_cmd_installed "start-stop-daemon" || log_error "start-stop-daemon not found. This is critical for service management. Please ensure it's installed (part of busybox/initscripts)."

# 2. Kiểm tra sự tồn tại của các script đã có sẵn
log_info "Verifying existence of existing scripts..."
if ! [ -f "${EXISTING_3GINFO_SCRIPT}" ]; then
    log_error "Script '${EXISTING_3GINFO_SCRIPT}' not found. This is critical for fetching modem data. Please ensure '3ginfo-lite' package is installed correctly."
    exit 1
fi
log_info "Found existing script: ${EXISTING_3GINFO_SCRIPT}"

# --- MANUAL STEP REQUIRED ---
log_warning "--------------------------------------------------------------------"
log_warning "MANUAL STEP REQUIRED: Please copy the following files/directories"
log_warning "from your local machine to '${APP_SOURCE_DIR}' ON THE ROUTER:"
log_warning "  - app.py"
log_warning "  - requirements.txt"
log_warning "  - static/ (directory containing css/ and js/)"
log_warning "  - templates/ (directory containing index.html)"
log_warning "  - ${VENV_TARBALL} (if you have a pre-built venv)"
log_warning "Then, press ENTER to continue after copying."
log_warning "--------------------------------------------------------------------"
read -p "Press Enter when files are copied..."

# --- Kiểm tra sự tồn tại của các tệp ứng dụng MỚI ---
log_info "Verifying required application files after copy..."
if ! [ -f "${APP_SOURCE_DIR}/app.py" ]; then log_error "app.py not found in ${APP_SOURCE_DIR}. Setup failed."; cleanup_failed_setup; exit 1; fi
if ! [ -f "${APP_SOURCE_DIR}/requirements.txt" ]; then log_error "requirements.txt not found in ${APP_SOURCE_DIR}. Setup failed."; cleanup_failed_setup; exit 1; fi
if ! [ -f "${APP_SOURCE_DIR}/templates/index.html" ]; then log_error "templates/index.html not found in ${APP_SOURCE_DIR}. Setup failed."; cleanup_failed_setup; exit 1; fi
if ! [ -f "${APP_SOURCE_DIR}/static/js/script.js" ]; then log_error "static/js/script.js not found in ${APP_SOURCE_DIR}. Setup failed."; cleanup_failed_setup; exit 1; fi

# 3. Tạo cấu trúc thư mục ứng dụng mới
log_info "Creating application directory structure at ${APP_BASE_DIR}..."
mkdir -p "${APP_BASE_DIR}/static/css"
mkdir -p "${APP_BASE_DIR}/static/js"
mkdir -p "${APP_BASE_DIR}/templates"
mkdir -p "${APP_BASE_DIR}/venv/bin"
# Tạo các thư mục cần thiết cho venv tùy theo phiên bản python
# Tìm phiên bản python để tạo đúng thư mục site-packages
PY_VERSION=$(basename "$(dirname "${PYTHON_CMD}")") # e.g., python3, python3.9, python3.10
# Fallback if PYTHON_CMD is just 'python3' and not a specific versioned path
if [[ "$PY_VERSION" == "bin" ]]; then
    PY_VERSION=$(python3 --version 2>/dev/null | awk '{print $2}' | cut -d. -f1,2)
    if [ -z "$PY_VERSION" ]; then PY_VERSION="python3.9"; fi # Default if unknown
fi
mkdir -p "${APP_BASE_DIR}/venv/lib/${PY_VERSION}/site-packages"

# Sao chép các tệp ứng dụng mới vào vị trí cài đặt cuối cùng
log_info "Copying application files to ${APP_BASE_DIR}..."
cp "${APP_SOURCE_DIR}/app.py" "${APP_BASE_DIR}/" || { log_error "Failed to copy app.py."; cleanup_failed_setup; exit 1; }
cp "${APP_SOURCE_DIR}/requirements.txt" "${APP_BASE_DIR}/" || { log_error "Failed to copy requirements.txt."; cleanup_failed_setup; exit 1; }
cp -r "${APP_SOURCE_DIR}/static" "${APP_BASE_DIR}/" || { log_error "Failed to copy static directory."; cleanup_failed_setup; exit 1; }
cp -r "${APP_SOURCE_DIR}/templates" "${APP_BASE_DIR}/" || { log_error "Failed to copy templates directory."; cleanup_failed_setup; exit 1; }

# Xử lý môi trường ảo
if [ -f "${APP_SOURCE_DIR}/${VENV_TARBALL}" ]; then
    log_info "Extracting virtual environment from ${VENV_TARBALL} to ${APP_BASE_DIR}/venv/..."
    tar -xzf "${APP_SOURCE_DIR}/${VENV_TARBALL}" -C "${APP_BASE_DIR}/venv/" || { log_error "Failed to extract virtual environment."; cleanup_failed_setup; exit 1; }
else
    log_info "No ${VENV_TARBALL} found. Creating new Python virtual environment at ${APP_BASE_DIR}/venv/..."
    cd "${APP_BASE_DIR}" || { log_error "Failed to change directory to ${APP_BASE_DIR} for venv creation."; cleanup_failed_setup; exit 1; }
    
    "${PYTHON_CMD}" -m venv venv || { log_error "Failed to create virtual environment."; cleanup_failed_setup; exit 1; }
fi

# Cài đặt thư viện Python vào venv
log_info "Installing Python dependencies from requirements.txt..."
"${APP_BASE_DIR}/venv/bin/pip" install -r "${APP_BASE_DIR}/requirements.txt" || { log_error "Failed to install Python dependencies. Please check requirements.txt and permissions."; cleanup_failed_setup; exit 1; }

# 4. Cấp quyền thực thi cho script 3ginfo.sh (chỉ để chắc chắn)
log_info "Ensuring execute permissions for existing script: ${EXISTING_3GINFO_SCRIPT}..."
chmod +x "${EXISTING_3GINFO_SCRIPT}" || log_warning "Failed to set execute permission for ${EXISTING_3GINFO_SCRIPT}."

# 5. Tạo init.d script cho dịch vụ dashboard
log_info("Creating init.d script at ${INIT_SCRIPT_PATH}...")

PYTHON_EXEC_IN_VENV="${APP_BASE_DIR}/venv/bin/python" # Đường dẫn chính xác tới python trong venv

INIT_SCRIPT_CONTENT=$(cat << EOF
#!/bin/sh /etc/rc.common
START=90
STOP=10
SERVICE_NAME="${SERVICE_NAME}"
APP_DIR="${APP_BASE_DIR}"
# Use the python executable from the virtual environment
PYTHON_EXEC="${PYTHON_EXEC_IN_VENV}" 
FLASK_APP_SCRIPT="${FLASK_APP_SCRIPT}"
PORT="${PORT}"
PID_FILE="${PID_FILE}"
LOG_FILE="${APP_BASE_DIR}/nohup.out"

# Ensure python executable exists
[ -x "${PYTHON_EXEC}" ] || { log_error "Python executable from venv not found at ${PYTHON_EXEC}."; exit 1; }

start() {
    log_info "Starting \${SERVICE_NAME}..."
    [ -d "\${APP_DIR}" ] || { log_error "App directory \${APP_DIR} missing."; return 1; }
    
    # Check if already running
    if [ -f "\${PID_FILE}" ]; then
        PID=\$(cat "\${PID_FILE}")
        if ps -p "\$PID" > /dev/null; then
            log_info "\${SERVICE_NAME} is already running (PID: \$PID)."
            return 0
        fi
    fi

    log_info "Starting \${SERVICE_NAME} with Python: \${PYTHON_EXEC} \${FLASK_APP_SCRIPT} on port \${PORT}"
    
    # Start using start-stop-daemon
    start-stop-daemon -S -b -p "\${PID_FILE}" -m -N "\${SERVICE_NAME}" -u root --chdir "\${APP_DIR}" --exec "\${PYTHON_EXEC}" -- "\${FLASK_APP_SCRIPT}"
    
    if [ \$? -eq 0 ]; then
        log_info "\${SERVICE_NAME} started successfully (PID: \$(cat "\${PID_FILE}"))."
    else
        log_error "Failed to start \${SERVICE_NAME}. Check logs."
        [ -f "\${PID_FILE}" ] && rm "\${PID_FILE}"
        return 1
    fi
}

stop() {
    log_info "Stopping ${SERVICE_NAME}..."
    start-stop-daemon -K -p "${PID_FILE}" --quiet
    if [ \$? -eq 0 ]; then
        log_info "${SERVICE_NAME} stopped successfully."
        rm -f "${PID_FILE}"
    else
        log_error "Failed to stop ${SERVICE_NAME}."
        return 1
    fi
}

restart() {
    stop
    sleep 2
    start
}

enable() {
    log_info "Enabling ${SERVICE_NAME} service..."
    chmod +x "${INIT_SCRIPT_PATH}"
    local LINK="/etc/rc.d/S90${SERVICE_NAME}" # Use a consistent symlink name
    if [ ! -L "\$LINK" ]; then
        ln -s "${INIT_SCRIPT_PATH}" "\$LINK"
        log_info "${SERVICE_NAME} enabled. It will start on boot."
    else
        log_info "${SERVICE_NAME} is already enabled."
    fi
}

disable() {
    log_info "Disabling ${SERVICE_NAME} service..."
    rm -f "/etc/rc.d/S90${SERVICE_NAME}"
    log_info "${SERVICE_NAME} disabled."
}

case "\$1" in
    start)
        service_start
        ;;
    stop)
        service_stop
        ;;
    restart)
        service_restart
        ;;
    enable)
        service_enable
        ;;
    disable)
        service_disable
        ;;
    status)
        if [ -f "${PID_FILE}" ]; then
            PID=\$(cat "${PID_FILE}")
            if ps -p "\$PID" > /dev/null; then
                echo "${SERVICE_NAME} is running (PID: \$PID)."
            else
                echo "${SERVICE_NAME} is stopped (stale PID file found)."
            fi
        else
            echo "${SERVICE_NAME} is stopped."
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|enable|disable|status}"
        exit 1
        ;;
esac
EOF
)
echo "$INIT_SCRIPT_CONTENT" > "$INIT_SCRIPT_PATH" || log_error "Failed to write init.d script."
chmod +x "$INIT_SCRIPT_PATH" || log_error "Failed to make init.d script executable."
log_info("init.d script created at ${INIT_SCRIPT_PATH}.")

# 6. Kích hoạt và Khởi động Dịch vụ
log_info("Enabling and starting the ${SERVICE_NAME} service...")
service "${SERVICE_NAME}" enable || log_warning("Failed to enable service. Check permissions.")
service "${SERVICE_NAME}" start || log_error("Failed to start the service. Check logs in ${APP_BASE_DIR}/nohup.out or /var/log/messages.")

# 7. Cấu hình uhttpd
UHTTPD_PROXY_SECTION="em9190_proxy" # Tên section tùy ý

log_info("Configuring uhttpd to serve static files and proxy API requests...")
# Kiểm tra xem section proxy đã tồn tại chưa
if ! uci show uhttpd | grep -q "config uhttpd '${UHTTPD_PROXY_SECTION}'"; then
    log_info("Adding uhttpd configuration for ${SERVICE_NAME}...")
    
    # Thêm section phục vụ tệp tĩnh
    uci add uhttpd files
    uci set uhttpd.@files[-1].home="${APP_BASE_DIR}"
    uci set uhttpd.@files[-1].index="index.html"
    
    # Thêm section cho proxy API
    uci add uhttpd proxy
    uci set uhttpd.@proxy[-1]=${UHTTPD_PROXY_SECTION} # Gán tên section
    uci set uhttpd.@proxy[-1].forward_host="127.0.0.1" # Flask chỉ lắng nghe trên localhost cho uhttpd proxy
    uci set uhttpd.@proxy[-1].forward_port="${PORT}"
    uci add_list uhttpd.@proxy[-1].forward_rule="/api.cgi* http"
    
    uci commit uhttpd || log_error "Failed to commit uhttpd configuration."
    log_info("uhttpd configuration added. Reloading uhttpd...")
    /etc/init.d/uhttpd reload || log_error("Failed to reload uhttpd. Please restart it manually: /etc/init.d/uhttpd restart")
else
    log_info("uhttpd configuration for ${SERVICE_NAME} already exists. Skipping addition.")
    # Tùy chọn: Nếu port có thể thay đổi, hãy cập nhật nó
    # uci set uhttpd."${UHTTPD_PROXY_SECTION}".forward_port="${PORT}"
    # uci commit uhttpd
    # /etc/init.d/uhttpd reload
fi

# --- Final Success Message ---
log_info "-----------------------------------------------------------"
log_info " EM9190 Dashboard Setup Script Finished."
log_info " Your EM9190 Dashboard should be accessible at:"
log_info "   http://<YOUR_ROUTER_IP>:${PORT}"
log_info "-----------------------------------------------------------"
log_info "If you encounter issues, check:"
log_info " - Permissions for ${APP_BASE_DIR} and its contents."
log_info " - Logs in ${APP_BASE_DIR}/nohup.out or via 'logread'."
log_info " - Service status: service ${SERVICE_NAME} status"
log_info " - uhttpd configuration: uci show uhttpd"
log_info " - Network connectivity: ifconfig"
log_info "-----------------------------------------------------------"

exit 0
