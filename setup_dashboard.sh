#!/bin/sh

# --- Configuration ---
APP_BASE_DIR="/www/em9190" # Thư mục cài đặt mới cho dashboard
APP_SOURCE_DIR="/root/em9190_files" # Thư mục nơi bạn đặt các tệp nguồn ứng dụng (trước khi setup)
# Đường dẫn tới script 3ginfo.sh đã có sẵn trên hệ thống
EXISTING_3GINFO_SCRIPT="/usr/share/3ginfo-lite/3ginfo.sh"

PYTHON_CMD="/usr/bin/python3" # Lệnh python3 hệ thống
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
log_error() { echo "[ERROR] $1"; return 1; } # Trả về mã lỗi

# Function to check if a command exists
check_cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install package and check for success
install_pkg() {
    local pkg_name="$1"
    local log_prefix="$2" # [INFO] or [ERROR]
    
    if check_cmd_exists "$pkg_name"; then
        log_info "$log_prefix: '$pkg_name' is already installed."
        return 0
    fi
    
    log_info "$log_prefix: '$pkg_name' not found. Attempting to install..."
    opkg update || log_error "$log_prefix: Failed to update opkg. Please check internet connection."
    opkg install "$pkg_name"
    if [ $? -eq 0 ]; then
        log_info "$log_prefix: '$pkg_name' installed successfully."
        return 0
    else
        log_error "$log_prefix: Failed to install '$pkg_name'. Please install it manually using 'opkg install $pkg_name'."
        return 1
    fi
}

# Function to clean up partial setup
cleanup_failed_setup() {
    log_warning "An error occurred. Attempting to clean up partially installed files..."
    # Stop the service if it's running
    if [ -f "$PID_FILE" ]; then
        log_warning "Stopping any running instance of ${SERVICE_NAME}..."
        start-stop-daemon -K -p "$PID_FILE" --quiet || true
        rm -f "$PID_FILE"
    fi
    # Remove the init.d script
    [ -f "$INIT_SCRIPT_PATH" ] && rm "$INIT_SCRIPT_PATH"
    # Note: Removing uhttpd config is complex and risky, better to leave it and let user manually fix.
    
    log_warning "Cleanup attempted. Please review logs and fix issues manually."
}

# --- Script Execution ---

log_info "--- Starting EM9190 Dashboard Setup ---"

# 1. Kiểm tra và cài đặt các gói cần thiết
log_info "Checking and installing necessary packages..."
if ! install_pkg python3 "[ERROR]"; then exit 1; fi
if ! install_pkg python3-pip "[ERROR]"; then exit 1; fi
if ! install_pkg python3-flask "[ERROR]"; then exit 1; fi
if ! install_pkg comgt "[INFO]"; then log_warning "comgt not installed. sms_tool might not work. Install it if needed."; fi # comgt is optional but recommended for sms_tool
if ! install_pkg screen "[INFO]"; then log_warning "screen not installed. Useful for managing processes."; fi

# Check for start-stop-daemon (critical for service management)
if ! check_cmd_exists "start-stop-daemon"; then
    log_error "Critical command 'start-stop-daemon' not found. This is essential for managing services on OpenWrt. Ensure initscripts package is installed."
    exit 1
fi

# 2. Kiểm tra sự tồn tại của các script đã có sẵn
log_info "Verifying existence of existing scripts..."
if ! [ -x "${EXISTING_3GINFO_SCRIPT}" ]; then
    log_error "Script '${EXISTING_3GINFO_SCRIPT}' not found or not executable. This is critical for fetching modem data. Please ensure '3ginfo-lite' package is installed correctly and the path is correct."
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
log_warning "  - ${VENV_TARBALL} (if you have a pre-built venv for your router's architecture)"
log_warning "Then, press ENTER to continue after copying."
log_warning "--------------------------------------------------------------------"
read -p "Press Enter when files are copied..."

# --- Kiểm tra sự tồn tại của các tệp ứng dụng MỚI SAU KHI sao chép ---
log_info "Verifying required application files after copy..."
if ! [ -f "${APP_SOURCE_DIR}/app.py" ]; then log_error "app.py not found in ${APP_SOURCE_DIR}. Setup failed."; cleanup_failed_setup; exit 1; fi
if ! [ -f "${APP_SOURCE_DIR}/requirements.txt" ]; then log_error "requirements.txt not found in ${APP_SOURCE_DIR}. Setup failed."; cleanup_failed_setup; exit 1; fi
if ! [ -f "${APP_SOURCE_DIR}/templates/index.html" ]; then log_error "templates/index.html not found in ${APP_SOURCE_DIR}. Setup failed."; cleanup_failed_setup; exit 1; fi
if ! [ -f "${APP_SOURCE_DIR}/static/js/script.js" ]; then log_error "static/js/script.js not found in ${APP_SOURCE_DIR}. Setup failed."; cleanup_failed_setup; exit 1; fi

# 3. Tạo cấu trúc thư mục ứng dụng mới và sao chép tệp
log_info "Creating application directory structure at ${APP_BASE_DIR}..."
mkdir -p "${APP_BASE_DIR}/static/css"
mkdir -p "${APP_BASE_DIR}/static/js"
mkdir -p "${APP_BASE_DIR}/templates"
# Tự động tạo thư mục venv nếu cần
if [ ! -d "${APP_BASE_DIR}/venv" ]; then
    log_info "Creating Python virtual environment directory at ${APP_BASE_DIR}/venv..."
    mkdir -p "${APP_BASE_DIR}/venv"
fi

# Sao chép các tệp ứng dụng mới vào vị trí cài đặt cuối cùng
log_info "Copying application files to ${APP_BASE_DIR}..."
cp "${APP_SOURCE_DIR}/app.py" "${APP_BASE_DIR}/" || { log_error "Failed to copy app.py."; cleanup_failed_setup; exit 1; }
cp "${APP_SOURCE_DIR}/requirements.txt" "${APP_BASE_DIR}/" || { log_error "Failed to copy requirements.txt."; cleanup_failed_setup; exit 1; }
cp -r "${APP_SOURCE_DIR}/static" "${APP_BASE_DIR}/" || { log_error "Failed to copy static directory."; cleanup_failed_setup; exit 1; }
cp -r "${APP_SOURCE_DIR}/templates" "${APP_BASE_DIR}/" || { log_error "Failed to copy templates directory."; cleanup_failed_setup; exit 1; }

# Xử lý môi trường ảo (tạo mới hoặc giải nén)
if [ -f "${APP_SOURCE_DIR}/${VENV_TARBALL}" ]; then
    log_info "Extracting virtual environment from ${VENV_TARBALL} to ${APP_BASE_DIR}/venv/..."
    # Cần đảm bảo thư mục venv trống hoặc xóa nội dung cũ nếu có
    rm -rf "${APP_BASE_DIR}/venv/*"
    tar -xzf "${APP_SOURCE_DIR}/${VENV_TARBALL}" -C "${APP_BASE_DIR}/venv/" || { log_error "Failed to extract virtual environment."; cleanup_failed_setup; exit 1; }
else
    log_info "No ${VENV_TARBALL} found. Creating new Python virtual environment at ${APP_BASE_DIR}/venv/..."
    # Xóa nội dung cũ nếu venv đã tồn tại nhưng không phải từ file nén
    [ -d "${APP_BASE_DIR}/venv" ] && rm -rf "${APP_BASE_DIR}/venv/*"
    
    "${PYTHON_CMD}" -m venv "${APP_BASE_DIR}/venv" || { log_error "Failed to create virtual environment."; cleanup_failed_setup; exit 1; }
fi

# Cài đặt thư viện Python vào venv
log_info "Installing Python dependencies from requirements.txt using venv's pip..."
"${APP_BASE_DIR}/venv/bin/pip" install -r "${APP_BASE_DIR}/requirements.txt" || { log_error "Failed to install Python dependencies. Please check requirements.txt and permissions."; cleanup_failed_setup; exit 1; }

# 4. Cấp quyền thực thi cho script 3ginfo.sh
log_info "Ensuring execute permissions for existing script: ${EXISTING_3GINFO_SCRIPT}..."
chmod +x "${EXISTING_3GINFO_SCRIPT}" || log_warning "Failed to set execute permission for ${EXISTING_3GINFO_SCRIPT}. Modem data fetching might fail."

# 5. Tạo init.d script cho dịch vụ dashboard
log_info("Creating init.d script at ${INIT_SCRIPT_PATH}...")

# Lấy đường dẫn chính xác tới python trong venv
PYTHON_EXEC_IN_VENV="${APP_BASE_DIR}/venv/bin/python"
# Đường dẫn tới script flask
FLASK_EXEC="${PYTHON_EXEC_IN_VENV} -m flask --app ${FLASK_APP_SCRIPT} --host 0.0.0.0 --port ${PORT}"

# Tách chuỗi để chạy lệnh flask qua start-stop-daemon
# Cần xử lý đặc biệt để shell thực thi đúng chuỗi lệnh này.
# Thay vì dùng `eval source`, ta trực tiếp gọi python từ venv.
# Flask sẽ tự tìm các tệp static/templates dựa trên thư mục CHDIR.

INIT_SCRIPT_CONTENT=$(cat << EOF
#!/bin/sh /etc/rc.common

START=90
STOP=10
SERVICE_NAME="${SERVICE_NAME}"
APP_DIR="${APP_BASE_DIR}"
# Use the specific python executable from the virtual environment
PYTHON_EXEC="${PYTHON_EXEC_IN_VENV}" 
# Command to run flask
FLASK_CMD="${FLASK_EXEC}"
PORT="${PORT}"
PID_FILE="${PID_FILE}"
LOG_FILE="${APP_BASE_DIR}/nohup.out"

# Ensure executable exists
[ -x "\${PYTHON_EXEC}" ] || { log_error "Python executable from venv not found at \${PYTHON_EXEC}. Cannot start service."; exit 1; }

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

    log_info "Starting \${SERVICE_NAME} using: \$(${PYTHON_CMD} --version) from venv at \${PYTHON_EXEC}"
    log_info "Running Flask app: \${FLASK_APP_SCRIPT} on port \${PORT}"
    
    # Using start-stop-daemon. The --exec should be the full command to run.
    # We need to ensure the command includes the python interpreter and its arguments.
    # --chdir is critical for Flask to find templates/static
    start-stop-daemon -S -b -p "\${PID_FILE}" -m -N "\${SERVICE_NAME}" -u root --chdir "\${APP_DIR}" --exec "\${PYTHON_EXEC}" -- \${FLASK_CMD//--host 0.0.0.0/} # Remove --host from the command passed to exec if needed, or ensure it's correctly handled.
                                                                                                                                        # The command passed to exec should be the interpreter followed by the script/module.
                                                                                                                                        # For Flask, it's `python -m flask run ...` or `python app.py`
                                                                                                                                        # Let's try calling python directly with the script.
    # Corrected start-stop-daemon exec:
    # start-stop-daemon -S -b -p "\${PID_FILE}" -m -N "\${SERVICE_NAME}" -u root --chdir "\${APP_DIR}" --exec "\${PYTHON_EXEC}" -- "\${FLASK_APP_SCRIPT}" # This might fail if script requires args or specific python env activation.
    # A safer way might be to use a wrapper script, or ensure FLASK_APP env var is set.
    # Let's stick to the simplest form for now:
    # start-stop-daemon -S -b -p "\${PID_FILE}" -m -N "\${SERVICE_NAME}" -u root --chdir "\${APP_DIR}" --exec "\${PYTHON_EXEC}" -- "-m" "flask" "run" "--host=0.0.0.0" "--port=${PORT}" "--app" "\${FLASK_APP_SCRIPT}"
    
    # Let's use the simplest: python app.py as originally in app.py
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
    local LINK="/etc/rc.d/S90${SERVICE_NAME}" # Use a consistent symlink name for startup
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
# Kiểm tra và thêm cấu hình uhttpd nếu chưa có
if ! uci show uhttpd | grep -q "config uhttpd '${UHTTPD_PROXY_SECTION}'"; then
    log_info("Adding uhttpd configuration for ${SERVICE_NAME}...")
    
    # Thêm section phục vụ tệp tĩnh
    uci add uhttpd files
    uci set uhttpd.@files[-1].home="${APP_BASE_DIR}"
    uci set uhttpd.@files[-1].index="index.html"
    
    # Thêm section cho proxy API
    uci add uhttpd proxy
    uci set uhttpd.@proxy[-1]=${UHTTPD_PROXY_SECTION} # Gán tên section
    # Flask sẽ lắng nghe trên tất cả các interface để uhttpd có thể proxy đến
    uci set uhttpd.@proxy[-1].forward_host="0.0.0.0" 
    uci set uhttpd.@proxy[-1].forward_port="${PORT}"
    uci add_list uhttpd.@proxy[-1].forward_rule="/api.cgi* http"
    
    uci commit uhttpd || log_error "Failed to commit uhttpd configuration."
    log_info("uhttpd configuration added. Reloading uhttpd...")
    /etc/init.d/uhttpd reload || log_error("Failed to reload uhttpd. Please restart it manually: /etc/init.d/uhttpd restart")
else
    log_info("uhttpd configuration for ${SERVICE_NAME} already exists. Skipping addition.")
    # Tùy chọn: Cập nhật port nếu cần thiết
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
