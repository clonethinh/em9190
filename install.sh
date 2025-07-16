#!/bin/sh
# install_complete.sh - Script cài đặt hoàn chỉnh EM9190 Monitor

# --- Xóa sạch các thành phần cũ nếu có ---
echo "🧹 Dọn dẹp các thành phần cũ..."
# Remove existing directories
if [ -d "/usr/share/em9190-monitor" ]; then
    rm -rf "/usr/share/em9190-monitor"
fi
if [ -d "/www/em9190" ]; then
    rm -rf "/www/em9190"
fi
# Remove old init script and log files
if [ -f "/etc/init.d/em9190-monitor" ]; then
    /etc/init.d/em9190-monitor stop >/dev/null 2>&1
    /etc/init.d/em9190-monitor disable >/dev/null 2>&1
    rm -f "/etc/init.d/em9190-monitor"
fi
if [ -f "/etc/config/em9190-monitor" ]; then
    rm -f "/etc/config/em9190-monitor"
fi
if [ -f "/var/log/uhttpd_em9190_access.log" ]; then
    rm -f "/var/log/uhttpd_em9190_access.log"
fi
if [ -f "/var/log/uhttpd_em9190_error.log" ]; then
    rm -f "/var/log/uhttpd_em9190_error.log"
fi
if [ -d "/tmp/modem" ]; then
    rm -rf "/tmp/modem"
fi
echo "✅ Dọn dẹp hoàn tất."
echo ""

# --- Cài đặt mặc định ---
DEFAULT_INSTALL_DIR="/usr/share/em9190-monitor"
DEFAULT_WEB_DIR="/www/em9190"
DEFAULT_PORT=9999
CONFIG_NAME="uhttpd_em9190"

# --- Parse các tùy chọn dòng lệnh ---
# These variables are used for initial setup and can be overridden by command-line arguments later
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
WEB_DIR="${WEB_DIR:-$DEFAULT_WEB_DIR}"
PORT="${PORT:-$DEFAULT_PORT}"

# --- Xử lý tùy chọn dòng lệnh ---
# Prioritize command-line arguments provided directly to the script
# This allows overriding defaults if script is run like: ./install_complete.sh --port 8080
shift $((OPTIND-1)) # Reset OPTIND in case it was used before (unlikely but safe)
while getopts ":p:i:w:" opt; do
  case $opt in
    p)
      PORT="$OPTARG"
      ;;
    i)
      INSTALL_DIR="$OPTARG"
      ;;
    w)
      WEB_DIR="$OPTARG"
      ;;
    \?)
      echo "Usage: $0 [-p <port>] [-i <install_dir>] [-w <web_dir>]" >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1)) # Remove the parsed options from the argument list

# --- Kiểm tra các gói cần thiết ---
echo "🔍 Kiểm tra dependencies..."
MISSING_DEPS=""

# Kiểm tra sự tồn tại của sms_tool (hoặc gcom có thể được dùng thay thế)
# We will use a robust detection method for the modem device in the script itself,
# so we only need the 'sms_tool' or 'gcom' command to be available.
if ! command -v sms_tool >/dev/null 2>&1; then
    if ! command -v gcom >/dev/null 2>&1; then
        MISSING_DEPS="$MISSING_DEPS sms-tool gcom"
    fi
fi

# Kiểm tra sự tồn tại của uhttpd
if ! command -v uhttpd >/dev/null 2>&1; then
    MISSING_DEPS="$MISSING_DEPS uhttpd"
fi

# Check if opkg is available and attempt to install if dependencies are missing
if [ -n "$MISSING_DEPS" ]; then
    echo "WARNING: Missing required packages: $MISSING_DEPS"
    echo "Attempting to install missing packages..."
    
    # Check for internet connection
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        echo "Internet connection detected. Running 'opkg update' and installing..."
        if opkg update; then
            echo "opkg update successful. Installing missing packages..."
            # Install all missing deps in one go for efficiency
            # Use --force-depends if necessary, but generally avoid unless needed.
            if opkg install $MISSING_DEPS; then
                echo "INFO: Missing packages installed successfully."
                # Re-check after installation
                if ! command -v sms_tool >/dev/null 2>&1 && ! command -v gcom >/dev/null 2>&1; then
                    MISSING_DEPS="$MISSING_DEPS (sms-tool/gcom install failed)"
                fi
                if ! command -v uhttpd >/dev/null 2>&1; then
                    MISSING_DEPS="$MISSING_DEPS (uhttpd install failed)"
                fi
            else
                echo "ERROR: 'opkg install $MISSING_DEPS' failed."
                MISSING_DEPS="$MISSING_DEPS (opkg install failed)"
            fi
        else
            echo "ERROR: 'opkg update' failed. Cannot install dependencies."
            MISSING_DEPS="$MISSING_DEPS (opkg update failed)"
        fi
    else
        echo "ERROR: No internet connection. Cannot install dependencies."
        MISSING_DEPS="$MISSING_DEPS (no internet connection)"
    fi
fi

# Final check for missing dependencies after attempted installation
if [ -n "$MISSING_DEPS" ]; then
    echo "ERROR: Failed to install one or more dependencies. Please install manually:"
    echo "       opkg update && opkg install $MISSING_DEPS"
    exit 1
fi
echo "✅ Dependencies are satisfied."
echo ""


set -e # Exit immediately if a command exits with a non-zero status.

echo "🚀 Cài đặt EM9190 Monitor (Thư mục: $INSTALL_DIR, Port: $PORT)..."

# --- Kiểm tra quyền root ---
if [ "$(id -u)" != "0" ]; then
    echo "❌ Script cần chạy với quyền root. Vui lòng sử dụng 'sudo ./install_complete.sh'"
    exit 1
fi

# --- Tạo thư mục cần thiết ---
echo "📁 Tạo cấu trúc thư mục..."
mkdir -p "$INSTALL_DIR"/{scripts,config,logs}
mkdir -p "$WEB_DIR"

# --- Hàm Tự động Phát hiện Thiết bị Modem (Enhanced) ---
# This function replaces the simple 'command -v' check for sms_tool
# and tries to find the actual modem device path.
# The enhanced version is placed in a separate file and sourced.
# The actual function definition is provided below in the 'detect_device.sh' block.

# --- Tạo Script phát hiện thiết bị modem (for API and main script) ---
echo "🛠️ Tạo script phát hiện thiết bị modem..."
cat > "$INSTALL_DIR/scripts/detect_device.sh" << 'EOF'
#!/bin/sh
# Provides the detect_device function for API scripts and the main installer.

# --- Helper function to get the sysfs path of a device ---
# This function attempts to find the underlying sysfs path for a given /dev/ device name.
# It's useful for linking /dev/ names to actual USB device hierarchies.
get_sys_path() {
    local dev_name="$1"
    local sys_path=""

    # Check common sysfs classes first
    for class in $(ls /sys/class/); do
        if [ -L "/sys/class/$class/$dev_name" ]; then
            sys_path="$(readlink -f "/sys/class/$class/$dev_name")"
            if [ -n "$sys_path" ]; then
                echo "$sys_path"
                return 0
            fi
        fi
    done
    
    # Try more specific USB device paths if not found in general classes
    # These might need adjustment based on kernel versions and USB device types
    if [ -d "/sys/devices/pci"* ] && [ -L "/sys/devices/pci"*"/usb"*"/drivers/"*"/net/$dev_name" ]; then
        sys_path="$(readlink -f "/sys/devices/pci"*"/usb"*"/drivers/"*"/net/$dev_name")"
        if [ -n "$sys_path" ]; then
            echo "$sys_path"
            return 0
        fi
    fi

    # Fallback for virtual or other complex USB structures
    if [ -d "/sys/devices/virtual/net/" ] && [ -L "/sys/devices/virtual/net/"*"/device/$dev_name" ]; then
        sys_path="$(readlink -f "/sys/devices/virtual/net/"*"/device/$dev_name")"
        if [ -n "$sys_path" ]; then
            echo "$sys_path"
            return 0
        fi
    fi
    
    # If still not found, try directly looking for the device name under USB busses
    if [ -e "/sys/bus/usb/devices/"*"/net/$dev_name" ]; then
        sys_path="$(readlink -f "/sys/bus/usb/devices/"*"/net/$dev_name")"
        if [ -n "$sys_path" ]; then
            echo "$sys_path"
            return 0
        fi
    fi

    return 1 # Not found
}

# --- Main detect_device function ---
detect_device() {
    local modem_device=""
    local potential_devices_from_dev=""
    local wan_device_name=""
    local wan_sys_path=""
    local preferred_tool=""

    # --- Determine the preferred tool (sms_tool or gcom) ---
    if command -v sms_tool >/dev/null 2>&1; then
        preferred_tool="sms_tool"
    elif command -v gcom >/dev/null 2>&1; then
        preferred_tool="gcom"
    fi

    # --- 1. Prioritize UCI configurations ---
    if command -v uci > /dev/null 2>&1; then
        local uci_defined_devices=""
        # Get device paths from UCI configurations
        uci_defined_devices+=$(uci -q get 3ginfo.@3ginfo[0].device 2>/dev/null)
        uci_defined_devices+=" $(uci -q get modemdefine.@modemdefine[0].comm_port 2>/dev/null)"
        uci_defined_devices+=" $(uci -q get modemdefine.@general[0].main_modem 2>/dev/null)"
        
        # Process each UCI defined device
        for uci_dev in $uci_defined_devices; do
            if [ -n "$uci_dev" ] && [ -e "$uci_dev" ]; then
                # If no validation tool, take the UCI device as is.
                if [ -z "$preferred_tool" ]; then
                    modem_device="$uci_dev"
                    echo "$modem_device" > /tmp/modem # Save found device
                    return 0
                fi
                
                # Validate the UCI device with the preferred tool
                local tool_cmd=""
                if [ "$preferred_tool" = "sms_tool" ]; then tool_cmd="sms_tool -d '$uci_dev' at 'AT'";
                elif [ "$preferred_tool" = "gcom" ]; then
                    # Ensure gcom check script exists
                    if [ -f "/usr/share/3ginfo-lite/check.gcom" ]; then
                        tool_cmd="gcom -d '$uci_dev' -s /usr/share/3ginfo-lite/check.gcom"
                    fi
                fi
                
                if [ -n "$tool_cmd" ] && timeout 3 sh -c "$tool_cmd" >/dev/null 2>&1; then
                    modem_device="$uci_dev"
                    echo "$modem_device" > /tmp/modem # Save found device
                    return 0 # Found and validated via UCI
                fi
            fi
        done
    fi

    # --- 2. Get WAN device name and its sysfs path ---
    wan_device_name=$(uci -q get network.wan.device 2>/dev/null)
    if [ -n "$wan_device_name" ]; then
        # Try to find the sysfs path for the WAN interface
        wan_sys_path=$(get_sys_path "$wan_device_name")
    fi

    # --- 3. Collect potential devices from /dev ---
    # Scan /dev for common modem patterns, sorted in reverse (prioritize newer devices)
    potential_devices_from_dev="$(find /dev -name "ttyUSB*" -o -name "ttyACM*" -o -name "wwan*at*" | sort -r)"
    
    # Filter for devices that match the WAN's sysfs path (if WAN is identified)
    local filtered_devices=""
    if [ -n "$wan_sys_path" ]; then
        # For each potential device from /dev, try to find its sysfs path
        # and compare it with the WAN's sysfs path. This mapping is tricky.
        # A more reliable way is to check if the sysfs path of /dev/ttyUSB*
        # is a child of the WAN's sysfs path.
        for dev_from_scan in $potential_devices_from_dev; do
            local dev_scan_sys_path=$(get_sys_path "$(basename "$dev_from_scan")")
            if [ -n "$dev_scan_sys_path" ] && [[ "$dev_scan_sys_path" == *"$wan_sys_path"* ]]; then
                filtered_devices="$filtered_devices $dev_from_scan"
            fi
        done
        # If filtering found devices, use them. Otherwise, fall back to unfiltered list.
        if [ -n "$filtered_devices" ]; then
            potential_devices_from_dev="$filtered_devices"
        fi
    fi
    
    # Deduplicate and clean the list from /dev
    potential_devices_from_dev=$(echo "$potential_devices_from_dev" | tr ' ' '\n' | sort -u | grep -v '^$' | grep -E '/dev/tty(USB|ACM|S0)[0-9]+|/dev/wwan[0-9]+at')

    # --- 4. Test each potential device from /dev ---
    if [ -z "$preferred_tool" ]; then
        # If no tools are available, we can't validate. Report an error.
        echo "" > /tmp/modem # Ensure /tmp/modem is empty
        return 1 # Indicate failure if no tools are present
    fi

    for DEVICE in $potential_devices_from_dev; do
        if [ -e "$DEVICE" ]; then
            local tool_cmd=""
            if [ "$preferred_tool" = "sms_tool" ]; then
                tool_cmd="sms_tool -d '$DEVICE' at 'AT'"
            elif [ "$preferred_tool" = "gcom" ]; then
                if [ -f "/usr/share/3ginfo-lite/check.gcom" ]; then
                    tool_cmd="gcom -d '$DEVICE' -s /usr/share/3ginfo-lite/check.gcom"
                fi
            fi

            if [ -n "$tool_cmd" ]; then
                # Run the command with a timeout and check exit code
                if timeout 5 sh -c "$tool_cmd" >/dev/null 2>&1; then
                    modem_device="$DEVICE"
                    echo "$modem_device" > /tmp/modem # Save found device
                    return 0 # Success
                fi
            fi
        fi
    done
    
    # --- 5. Final fallback if nothing found ---
    # If we reached here, no validated device was found.
    echo "" > /tmp/modem # Ensure /tmp/modem is empty
    return 1
}
EOF
chmod +x "$INSTALL_DIR/scripts/detect_device.sh"


# --- Tạo API Handler (/api.cgi) ---
echo "🔧 Tạo API handler..."
cat > "$WEB_DIR/api.cgi" << 'EOF'
#!/bin/sh
# CGI API handler cho EM9190 Monitor

# --- Cấu hình Header ---
echo "Content-Type: application/json"
echo "Cache-Control: no-cache, no-store, must-revalidate"
echo "Pragma: no-cache"
echo "Expires: 0"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, POST, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""

# --- Xử lý OPTIONS Request ---
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    exit 0
fi

# --- Parse Query String ---
QUERY_STRING="${QUERY_STRING:-}"
ACTION="info"

case "$QUERY_STRING" in
    *action=info*) ACTION="info" ;;
    *action=status*) ACTION="status" ;;
    *action=reset*) ACTION="reset" ;;
    *) ;; # Use default ACTION="info"
esac

# --- Hàm Trả về Lỗi ---
error_response() {
    local message="$1"
    cat <<EOFERR
{
    "error": true,
    "message": "${message:-Lỗi không xác định}",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOFERR
    exit 1
}

# --- Hàm Tự động Phát hiện Thiết bị Modem (uses the detect_device function from the main script) ---
# Source the detect_device function from the script we just created.
# Ensure INSTALL_DIR is correctly set here.
if [ -f "$INSTALL_DIR/scripts/detect_device.sh" ]; then
    . "$INSTALL_DIR/scripts/detect_device.sh"
else
    error_response "Không thể tìm thấy script phát hiện thiết bị modem: $INSTALL_DIR/scripts/detect_device.sh"
fi

# --- Xử lý các Action ---
case "$ACTION" in
    "info")
        DEVICE=$(detect_device)
        if [ -z "$DEVICE" ]; then
            error_response "Không tìm thấy thiết bị modem tương thích."
        fi
        
        if [ -x "$INSTALL_DIR/scripts/em9190_info.sh" ]; then
            "$INSTALL_DIR/scripts/em9190_info.sh" "$DEVICE"
        else
            error_response "Script $INSTALL_DIR/scripts/em9190_info.sh không tồn tại hoặc không có quyền thực thi."
        fi
        ;;
        
    "status")
        DEVICE=$(detect_device)
        DEVICE_STATUS="disconnected"
        [ -n "$DEVICE" ] && DEVICE_STATUS="connected"
        
        WAN_IP="-"
        WAN_INTERFACE=""

        # --- Improved WAN IP Detection ---
        # Try to find the WWAN interface directly (common names)
        WAN_INTERFACE=$(ip link show | awk '/state UP/ && /eth.*|wwan.*|usb/ {print $2}' | sed 's/://' | grep -E 'eth|wwan|usb' | head -n 1)
        
        # Fallback: Find the interface used for the default route
        if [ -z "$WAN_INTERFACE" ]; then
            DEFAULT_ROUTE_IP=$(ip route show default | grep default | awk '/default via/ {print $3}' | head -n 1)
            if [ -n "$DEFAULT_ROUTE_IP" ]; then
                WAN_INTERFACE=$(ip route get $DEFAULT_ROUTE_IP | grep -oP 'dev \K\S+' | head -n 1)
            fi
        fi

        if [ -n "$WAN_INTERFACE" ]; then
            # Get the IP address for the found interface
            WAN_IP=$(ip addr show $WAN_INTERFACE 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            # If no IPv4, try to get IPv6 (optional, for completeness)
            if [ -z "$WAN_IP" ] || [ "$WAN_IP" == "::1" ]; then
                WAN_IP=$(ip addr show $WAN_INTERFACE 2>/dev/null | grep "inet6 " | grep -v "::1/128" | awk '{print $2}' | cut -d/ -f1)
            fi
        fi
        
        # Further fallback: Check common modem interfaces directly if no interface was identified clearly
        if [ -z "$WAN_IP" ] || [ "$WAN_IP" == "-" ]; then
            for intf in wwan0 ppp0 usb0 eth0 eth1 eth2 eth3 eth4; do # Added eth0-4 as fallback
                if ip addr show $intf >/dev/null 2>&1; then
                    IP_ADDR=$(ip addr show $intf | grep "inet " | awk '{print $2}' | cut -d/ -f1)
                    if [ -n "$IP_ADDR" ] && [ "$IP_ADDR" != "-" ] && [[ ! "$IP_ADDR" =~ ^127\. ]]; then # Exclude localhost
                        WAN_IP="$IP_ADDR"
                        break
                    fi
                fi
            done
        fi

        WAN_IP="${WAN_IP:-"-"}" # Ensure it's always set, default to "-" if all attempts fail
        
        UPTIME_INFO=$(uptime | awk '{print $3,$4}' | sed 's/,//')
        
        cat <<EOFSTATUS
{
    "system_status": "online",
    "device_status": "$DEVICE_STATUS",
    "wan_ip": "$WAN_IP",
    "device_path": "${DEVICE:--}",
    "uptime": "$UPTIME_INFO",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOFSTATUS
        ;;
        
    "reset")
        DEVICE=$(detect_device)
        if [ -n "$DEVICE" ]; then
            # Log the attempt to reset
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Attempting modem reset on $DEVICE" >> "$INSTALL_DIR/logs/em9190_monitor.log"
            
            # Send AT+CFUN=1,1 command to reset the modem
            # Use sms_tool if available, else gcom
            local reset_cmd=""
            if command -v sms_tool >/dev/null 2>&1; then
                reset_cmd="sms_tool -d '$DEVICE' at 'AT+CFUN=1,1'"
            elif command -v gcom >/dev/null 2>&1; then
                # Assuming reset.gcom exists for gcom. If not, this needs to be adapted.
                if [ -f "/usr/share/3ginfo-lite/reset.gcom" ]; then
                    reset_cmd="gcom -d '$DEVICE' -s /usr/share/3ginfo-lite/reset.gcom"
                fi
            fi
            
            if [ -n "$reset_cmd" ]; then
                timeout 15 sh -c "$reset_cmd" >/dev/null 2>&1
            fi
            
            cat <<EOFRESET
{
    "success": true,
    "message": "Đã gửi lệnh reset modem. Modem sẽ khởi động lại.",
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')"
}
EOFRESET
        else
            error_response "Không tìm thấy thiết bị modem để reset."
        fi
        ;;
        
    *)
        error_response "Hành động không hợp lệ: $ACTION"
        ;;
esac
EOF

# --- Tạo Script lấy thông tin Modem (/usr/share/em9190-monitor/scripts/em9190_info.sh) ---
echo "📊 Tạo script lấy thông tin modem..."
cat > "$INSTALL_DIR/scripts/em9190_info.sh" << 'EOF'
#!/bin/sh
# Script lấy thông tin chi tiết của modem EM9190

DEVICE="${1:-}" # Lấy tên thiết bị từ tham số đầu tiên

if [ -z "$DEVICE" ]; then
    echo '{"error": true, "message": "Không có tên thiết bị modem nào được cung cấp."}'
    exit 1
fi

# Import các hàm tra cứu băng tần
. "$INSTALL_DIR/scripts/band_lookup.sh"

# --- Lấy thông tin từ modem ---
# Try to get modem info. Capture stderr for better error reporting.
# Use AT+CMNWINFO? which is commonly supported by Quectel modules like EM9190 for detailed info
# If that fails, fall back to AT!GSTATUS? or other known commands.

MODEM_INFO_OUTPUT=""
USE_SMS_TOOL=true
if command -v sms_tool >/dev/null 2>&1; then
    TOOL_CMD="sms_tool"
elif command -v gcom >/dev/null 2>&1; then
    TOOL_CMD="gcom"
    USE_SMS_TOOL=false
else
    echo '{"error": true, "message": "Không tìm thấy công cụ sms_tool hoặc gcom."}'
    exit 1
fi

# Attempting to get info using specific commands
CMD_TO_TRY=""
if [ "$USE_SMS_TOOL" = true ]; then
    # AT+CMNWINFO? is preferred for Quectel, AT!GSTATUS? is a fallback
    CMD_TO_TRY=$(timeout 5 $TOOL_CMD -d "$DEVICE" at "AT+CMNWINFO?" 2>/tmp/gstatus_err.log)
    if [ $? -ne 0 ] || [ -z "$CMD_TO_TRY" ] || [[ "$CMD_TO_TRY" == *"ERROR"* ]]; then
        CMD_TO_TRY=$(timeout 5 $TOOL_CMD -d "$DEVICE" at "AT!GSTATUS?" 2>/tmp/gstatus_err.log)
    fi
else # using gcom
    # gcom requires a script file. Assuming a check.gcom exists and is suitable.
    # If not, this part needs adjustment for gcom's command structure.
    # For gcom, we might need to execute a specific AT command via a script
    # Let's assume a common AT command retrieval works here.
    # If /usr/share/3ginfo-lite/check.gcom is for general info, it might work.
    if [ -f "/usr/share/3ginfo-lite/check.gcom" ]; then
        CMD_TO_TRY=$(timeout 10 $TOOL_CMD -d "$DEVICE" -s /usr/share/3ginfo-lite/check.gcom 2>/tmp/gstatus_err.log)
    fi
fi

# Process the retrieved output
if [ -n "$CMD_TO_TRY" ]; then
    MODEM_INFO_OUTPUT="$CMD_TO_TRY"
    GSTATUS_EXIT_CODE=0
else
    GSTATUS_EXIT_CODE=$?
    ERROR_MSG=$(cat /tmp/gstatus_err.log)
    MODEM_INFO_OUTPUT=""
fi
rm -f /tmp/gstatus_err.log # Clean up error log

if [ $GSTATUS_EXIT_CODE -ne 0 ] || [ -z "$MODEM_INFO_OUTPUT" ]; then
    echo '{"error": true, "message": "Lỗi khi giao tiếp với modem (Exit code: '$GSTATUS_EXIT_CODE'). '"$(echo "${ERROR_MSG:-Lỗi không xác định từ tool}" | tr -d '\r\n' | sed 's/"/\\"/g')"'", "exit_code": '$GSTATUS_EXIT_CODE'}'
    exit 1
fi

# --- Trích xuất các thông tin cụ thể ---
# Commands like AT+CMNWINFO? and AT!GSTATUS? can have different output formats.
# We'll try to parse common fields, prioritizing AT+CMNWINFO? if it seems to be the source.

MODEL=""
FW=""
TEMP=""
MODE=""
TAC_HEX=""
TAC_DEC=""
RSSI=""
RSRP=""
RSRQ=""
SINR=""
LTE_BAND_RAW=""
LTE_BW=""
NR5G_BAND_RAW=""
NR_BW=""

# Generic parsing logic that tries to accommodate different outputs
# Prioritize fields from AT+CMNWINFO? if available, otherwise use AT!GSTATUS? fields

# Model and Revision (Firmware)
if echo "$MODEM_INFO_OUTPUT" | grep -q "Product:"; then
    MODEL=$(echo "$MODEM_INFO_OUTPUT" | awk -F: '/Product:/ {getline; print $2}' | xargs)
    FW=$(echo "$MODEM_INFO_OUTPUT" | awk -F: '/Revision:/ {getline; print $2}' | xargs)
elif echo "$MODEM_INFO_OUTPUT" | grep -q "Revision"; then
    FW=$(echo "$MODEM_INFO_OUTPUT" | awk '/Revision:/ {print $2}' | xargs)
    MODEL="EM9190" # Assume EM9190 if specific model isn't found but FW is.
fi
# Fallback for model if not found
[ -z "$MODEL" ] && MODEL="EM9190" # Default to EM9190 if not found

# Temperature
if echo "$MODEM_INFO_OUTPUT" | grep -q "Temperature"; then
    TEMP=$(echo "$MODEM_INFO_OUTPUT" | awk -F: '/Temperature:/ {print $2}' | xargs)
    [ -n "$TEMP" ] && TEMP="${TEMP}°C"
fi

# System Mode
MODE_RAW=""
if echo "$MODEM_INFO_OUTPUT" | grep -q "System mode"; then
    MODE_RAW=$(echo "$MODEM_INFO_OUTPUT" | awk '/System mode:/ {print $3}')
elif echo "$MODEM_INFO_OUTPUT" | grep -q "Current Network:"; then
    MODE_RAW=$(echo "$MODEM_INFO_OUTPUT" | awk '/Current Network:/ {print $3}')
fi

case "$MODE_RAW" in
    "LTE") MODE="LTE" ;;
    "ENDC") MODE="5G NSA" ;;
    "NRNSA") MODE="5G NSA" ;;
    "NRSA") MODE="5G SA" ;;
    "NR") MODE="5G SA" ;; # Assuming NR alone might mean SA
    "NR_NSA") MODE="5G NSA" ;;
    "CAT") MODE="LTE" ;; # Assuming CAT might mean LTE Cat
    "eMTC") MODE="LTE" ;;
    "NB-IoT") MODE="LTE" ;;
    *) MODE="Unknown" ;;
esac

# TAC
if echo "$MODEM_INFO_OUTPUT" | grep -q "TAC:"; then
    TAC_HEX=$(echo "$MODEM_INFO_OUTPUT" | awk '/TAC:/ {print $2}' | tr -d '\r\n')
fi
TAC_DEC=""
if [ -n "$TAC_HEX" ] && [ "$TAC_HEX" != "---" ]; then
    TAC_DEC=$(printf "%d" "0x$TAC_HEX" 2>/dev/null)
fi

# Signal Quality (PCC - Primary Carrier)
# AT+CMNWINFO? output format:
# SIM Status: 1
# Signal: -85 dBm
# RSRP: -103 dBm
# RSRQ: -12 dB
# SINR: 5 dB
# TX Power: 20 dBm

# AT!GSTATUS? output format (example):
# !GSTATUS:
#  Current Time: B02054C2
#  Time to time: 0
#  Time to start: 0
#  System Mode: LTE Category 12
#  Network Mode: Automatic
#  Current PLMN: 00000
#  LTE Band: B1 (2100)
#  LTE Bandwidth: 20 Mhz
#  LTE RSSI: -75 dBm
#  LTE RSRP: -95 dBm
#  LTE RSRQ: -8 dB
#  LTE SINR: 6 dB

# Parse common signal parameters
if echo "$MODEM_INFO_OUTPUT" | grep -q "Signal:"; then # Likely AT+CMNWINFO?
    RSSI=$(echo "$MODEM_INFO_OUTPUT" | awk '/Signal:/ {print $2}' | xargs)
    RSRP=$(echo "$MODEM_INFO_OUTPUT" | awk '/RSRP:/ {print $2}' | xargs)
    RSRQ=$(echo "$MODEM_INFO_OUTPUT" | awk '/RSRQ:/ {print $2}' | xargs)
    SINR=$(echo "$MODEM_INFO_OUTPUT" | awk '/SINR:/ {print $2}' | xargs)
    LTE_BAND_RAW=$(echo "$MODEM_INFO_OUTPUT" | awk '/LTE band:/ {print $3}' | sed 's/B//') # Extract band number without 'B'
    LTE_BW=$(echo "$MODEM_INFO_OUTPUT" | awk '/LTE Bandwidth:/ {print $3}' | sed 's/Mhz//')
elif echo "$MODEM_INFO_OUTPUT" | grep -q "LTE RSSI:"; then # Likely AT!GSTATUS?
    RSSI=$(echo "$MODEM_INFO_OUTPUT" | awk '/LTE RSSI:/ {print $3}' | xargs)
    RSRP=$(echo "$MODEM_INFO_OUTPUT" | awk '/LTE RSRP:/ {print $3}' | xargs)
    RSRQ=$(echo "$MODEM_INFO_OUTPUT" | awk '/LTE RSRQ:/ {print $3}' | xargs)
    SINR=$(echo "$MODEM_INFO_OUTPUT" | awk '/LTE SINR:/ {print $3}' | xargs)
    LTE_BAND_RAW=$(echo "$MODEM_INFO_OUTPUT" | awk '/LTE Band:/ {print $3}' | sed 's/(.*)//' | sed 's/B//') # Extract band number without 'B' and parentheses
    LTE_BW=$(echo "$MODEM_INFO_OUTPUT" | awk '/LTE Bandwidth:/ {print $3}' | sed 's/Mhz//')
fi

# --- Secondary Carriers (SCC) and 5G NR ---
# AT+CMNWINFO? does not typically provide SCC details, AT!GSTATUS? might.
# We'll look for common patterns for 5G NR details.

NR_RSRP="", NR_RSRQ="", NR_SINR="", NR_BAND=""
if echo "$MODEM_INFO_OUTPUT" | grep -q "NR RSRP:"; then # Common for some modules
    NR_RSRP=$(echo "$MODEM_INFO_OUTPUT" | awk '/NR RSRP:/ {print $3}' | xargs)
    NR_RSRQ=$(echo "$MODEM_INFO_OUTPUT" | awk '/NR RSRQ:/ {print $3}' | xargs)
    NR_SINR=$(echo "$MODEM_INFO_OUTPUT" | awk '/NR SINR:/ {print $3}' | xargs)
    NR_BAND=$(echo "$MODEM_INFO_OUTPUT" | awk '/NR Band:/ {print $3}' | sed 's/n//') # Extract band number without 'n'
elif echo "$MODEM_INFO_OUTPUT" | grep -q "Current Network: NR"; then # If mode is already 5G
    # Try to find NR-specific signal metrics if not already parsed
    if [ -z "$NR_RSRP" ] && echo "$MODEM_INFO_OUTPUT" | grep -q "RSRP:"; then # Might be generic RSRP for 5G
        NR_RSRP=$(echo "$MODEM_INFO_OUTPUT" | awk '/RSRP:/ {print $2}' | xargs)
        NR_RSRQ=$(echo "$MODEM_INFO_OUTPUT" | awk '/RSRQ:/ {print $2}' | xargs)
        NR_SINR=$(echo "$MODEM_INFO_OUTPUT" | awk '/SINR:/ {print $2}' | xargs)
    fi
fi

# --- Determine Primary and Secondary Bands ---
PBAND="-"
S1BAND="-"
NR5G_BAND="-"

# Process LTE band
if [ -n "$LTE_BAND_RAW" ] && [ "$LTE_BAND_RAW" != "---" ]; then
    PBAND="$(band4g "${LTE_BAND_RAW}")"
    [ -n "$LTE_BW" ] && PBAND="$PBAND @${LTE_BW} MHz"
fi

# Process 5G NR band
if [ -n "$NR_BAND" ] && [ "$NR_BAND" != "---" ]; then
    NR5G_BAND="$(band5g "${NR_BAND}")"
    # If 5G is active, it's generally the primary connection for data.
    # We can overwrite PBAND with NR5G_BAND or list it separately.
    # Let's list it separately for clarity and keep PBAND for LTE if present.
    # If Mode is 5G NSA/SA and only NR band is found, we might set PBAND to it.
    if [ "$MODE" = "5G NSA" ] || [ "$MODE" = "5G SA" ]; then
        if [ -z "$PBAND" ] || [ "$PBAND" = "-" ]; then # If no LTE band was detected
             PBAND="$NR5G_BAND"
        fi
        # If NR band is present, prioritize its signal metrics
        [ -n "$NR_RSRP" ] && RSRP="$NR_RSRP"
        [ -n "$NR_RSRQ" ] && RSRQ="$NR_RSRQ"
        [ -n "$NR_SINR" ] && SINR="$NR_SINR"
    fi
fi

# --- Fetch Band Description using lookup script ---
if [ -n "$LTE_BAND_RAW" ]; then PBAND="$(band4g ${LTE_BAND_RAW})"; fi
if [ -n "$LTE_BW" ]; then PBAND="$PBAND @${LTE_BW} MHz"; fi

if [ -n "$NR_BAND" ]; then NR5G_BAND="$(band5g ${NR_BAND})"; fi
if [ -n "$NR_BW" ]; then NR5G_BAND="$NR5G_BAND @${NR_BW} MHz"; fi

# --- Update Mode if CA or NR is active ---
if [ -n "$LTE_BAND_RAW" ] && [ -n "$NR_BAND" ]; then
    MODE="5G NSA" # If both LTE and NR are present, it's likely NSA
elif [ -n "$LTE_BAND_RAW" ] && echo "$MODEM_INFO_OUTPUT" | grep -q "LTE Bandwidth:"; then
    # Check for carrier aggregation indicators, e.g., if multiple bands are reported by other commands.
    # This parsing is basic. More sophisticated parsing might be needed.
    : # Placeholder for CA detection
fi


# --- Xuất kết quả dưới dạng JSON ---
cat <<EOFINFO
{
    "timestamp": "$(date '+%Y-%m-%d %H:%M:%S')",
    "modem": "${MODEL:-Unknown}",
    "firmware": "${FW:-Unknown}",
    "temperature": "${TEMP:--}",
    "mode": "${MODE:-Unknown}",
    "primary_band": "${PBAND:- -}",
    "secondary_band": "${S1BAND:- -}",
    "nr5g_band": "${NR5G_BAND:- -}",
    "tac_hex": "${TAC_HEX:--}",
    "tac_dec": "${TAC_DEC:--}",
    "signal": {
        "rssi": "${RSSI:--}",
        "rsrp": "${RSRP:--}",
        "rsrq": "${RSRQ:--}",
        "sinr": "${SINR:--}"
    },
    "device_path": "$DEVICE"
}
EOFINFO
EOF

# --- Tạo Script tra cứu Băng tần (/usr/share/em9190-monitor/scripts/band_lookup.sh) ---
echo "📡 Tạo script tra cứu băng tần..."
cat > "$INSTALL_DIR/scripts/band_lookup.sh" << 'EOF'
#!/bin/sh
# Các hàm tra cứu tên và tần số của băng tần mạng di động

band4g() {
    local band_num="$1"
    echo -n "B${band_num}"
    case "${band_num}" in
        "1") echo -n " (2100 MHz)" ;; "2") echo -n " (1900 MHz)" ;; "3") echo -n " (1800 MHz)" ;;
        "4") echo -n " (1700 MHz)" ;; "5") echo -n " (850 MHz)" ;; "7") echo -n " (2600 MHz)" ;;
        "8") echo -n " (900 MHz)" ;; "11") echo -n " (1500 MHz)" ;; "12") echo -n " (700 MHz)" ;;
        "13") echo -n " (700 MHz)" ;; "14") echo -n " (700 MHz)" ;; "17") echo -n " (700 MHz)" ;;
        "18") echo -n " (850 MHz)" ;; "19") echo -n " (850 MHz)" ;; "20") echo -n " (800 MHz)" ;;
        "21") echo -n " (1500 MHz)" ;; "24") echo -n " (1600 MHz)" ;; "25") echo -n " (1900 MHz)" ;;
        "26") echo -n " (850 MHz)" ;; "28") echo -n " (700 MHz)" ;; "29") echo -n " (700 MHz)" ;;
        "30") echo -n " (2300 MHz)" ;; "31") echo -n " (450 MHz)" ;; "32") echo -n " (1500 MHz)" ;;
        "34") echo -n " (2000 MHz)" ;; "37") echo -n " (1900 MHz)" ;; "38") echo -n " (2600 MHz)" ;;
        "39") echo -n " (1900 MHz)" ;; "40") echo -n " (2300 MHz)" ;; "41") echo -n " (2500 MHz)" ;;
        "42") echo -n " (3500 MHz)" ;; "43") echo -n " (3700 MHz)" ;; "46") echo -n " (5200 MHz)" ;;
        "47") echo -n " (5900 MHz)" ;; "48") echo -n " (3500 MHz)" ;; "50") echo -n " (1500 MHz)" ;;
        "51") echo -n " (1500 MHz)" ;; "53") echo -n " (2400 MHz)" ;; "54") echo -n " (1600 MHz)" ;;
        "65") echo -n " (2100 MHz)" ;; "66") echo -n " (1700 MHz)" ;; "67") echo -n " (700 MHz)" ;;
        "69") echo -n " (2600 MHz)" ;; "70") echo -n " (1700 MHz)" ;; "71") echo -n " (600 MHz)" ;;
        "72") echo -n " (450 MHz)" ;; "73") echo -n " (450 MHz)" ;; "74") echo -n " (1500 MHz)" ;;
        "75") echo -n " (1500 MHz)" ;; "76") echo -n " (1500 MHz)" ;; "85") echo -n " (700 MHz)" ;;
        "87") echo -n " (410 MHz)" ;; "88") echo -n " (410 MHz)" ;; "103") echo -n " (700 MHz)" ;;
        "106") echo -n " (900 MHz)" ;;
        *) echo -n " (Unknown)" ;;
    esac
}

band5g() {
    local band_num="$1"
    echo -n "n${band_num}"
    case "${band_num}" in
        "1") echo -n " (2100 MHz)" ;; "2") echo -n " (1900 MHz)" ;; "3") echo -n " (1800 MHz)" ;;
        "5") echo -n " (850 MHz)" ;; "7") echo -n " (2600 MHz)" ;; "8") echo -n " (900 MHz)" ;;
        "12") echo -n " (700 MHz)" ;; "13") echo -n " (700 MHz)" ;; "14") echo -n " (700 MHz)" ;;
        "18") echo -n " (850 MHz)" ;; "20") echo -n " (800 MHz)" ;; "24") echo -n " (1600 MHz)" ;;
        "25") echo -n " (1900 MHz)" ;; "26") echo -n " (850 MHz)" ;; "28") echo -n " (700 MHz)" ;;
        "29") echo -n " (700 MHz)" ;; "30") echo -n " (2300 MHz)" ;; "34") echo -n " (2100 MHz)" ;;
        "38") echo -n " (2600 MHz)" ;; "39") echo -n " (1900 MHz)" ;; "40") echo -n " (2300 MHz)" ;;
        "41") echo -n " (2500 MHz)" ;; "46") echo -n " (5200 MHz)" ;; "47") echo -n " (5900 MHz)" ;;
        "48") echo -n " (3500 MHz)" ;; "50") echo -n " (1500 MHz)" ;; "51") echo -n " (1500 MHz)" ;;
        "53") echo -n " (2400 MHz)" ;; "54") echo -n " (1600 MHz)" ;; "65") echo -n " (2100 MHz)" ;;
        "66") echo -n " (1700/2100 MHz)" ;; "67") echo -n " (700 MHz)" ;; "70") echo -n " (2000 MHz)" ;;
        "71") echo -n " (600 MHz)" ;; "74") echo -n " (1500 MHz)" ;; "75") echo -n " (1500 MHz)" ;;
        "76") echo -n " (1500 MHz)" ;; "77") echo -n " (3700 MHz)" ;; "78") echo -n " (3500 MHz)" ;;
        "79") echo -n " (4700 MHz)" ;; "80") echo -n " (1800 MHz)" ;; "81") echo -n " (900 MHz)" ;;
        "82") echo -n " (800 MHz)" ;; "83") echo -n " (700 MHz)" ;; "84") echo -n " (2100 MHz)" ;;
        "85") echo -n " (700 MHz)" ;; "86") echo -n " (1700 MHz)" ;; "89") echo -n " (850 MHz)" ;;
        "90") echo -n " (2500 MHz)" ;; "91") echo -n " (800/1500 MHz)" ;; "92") echo -n " (800/1500 MHz)" ;;
        "93") echo -n " (900/1500 MHz)" ;; "94") echo -n " (900/1500 MHz)" ;; "95") echo -n " (2100 MHz)" ;;
        "96") echo -n " (6000 MHz)" ;; "97") echo -n " (2300 MHz)" ;; "98") echo -n " (1900 MHz)" ;;
        "99") echo -n " (1600 MHz)" ;; "100") echo -n " (900 MHz)" ;; "101") echo -n " (1900 MHz)" ;;
        "102") echo -n " (6200 MHz)" ;; "104") echo -n " (6700 MHz)" ;; "105") echo -n " (600 MHz)" ;;
        "106") echo -n " (900 MHz)" ;; "109") echo -n " (700/1500 MHz)" ;;
        *) echo -n " (Unknown)" ;;
    esac
}
EOF

# --- Tạo Giao diện Web (index.html) ---
echo "🌐 Tạo giao diện web..."
cat > "$WEB_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sierra Wireless EM9190 Monitor</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&family=Roboto+Mono:wght@400;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        :root {
            --primary-color: #4A90E2; /* Blue */
            --secondary-color: #50E3C2; /* Teal */
            --background-gradient-start: #f0f4f8; /* Light Grayish Blue */
            --background-gradient-end: #dce4ee;  /* Lighter Blue */
            --card-background: #ffffff;
            --text-primary: #333;
            --text-secondary: #555;
            --text-accent: var(--primary-color);
            --border-color: #e0e0e0;
            --success-color: #4CAF50;
            --warning-color: #FF9800;
            --danger-color: #F44336;
            --shadow-color: rgba(0, 0, 0, 0.08);
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Inter', sans-serif;
            color: var(--text-primary);
        }

        body {
            background: linear-gradient(135deg, var(--background-gradient-start) 0%, var(--background-gradient-end) 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: flex-start;
            padding: 20px;
            overflow-x: hidden;
        }

        .container {
            width: 100%;
            max-width: 1100px;
            margin: 0 auto;
            text-align: center;
        }

        header {
            margin-bottom: 40px;
            padding-top: 20px;
        }

        header h1 {
            font-size: clamp(2rem, 6vw, 3rem);
            font-weight: 700;
            color: var(--text-accent);
            margin-bottom: 10px;
            letter-spacing: -0.5px;
        }

        .status-indicator {
            display: inline-flex;
            align-items: center;
            gap: 10px;
            background: rgba(255, 255, 255, 0.6);
            padding: 10px 20px;
            border-radius: 30px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.05);
            backdrop-filter: blur(8px);
            font-weight: 600;
            font-size: 1.1em;
            flex-wrap: wrap;
            justify-content: center;
        }

        .status-indicator .dot {
            width: 14px;
            height: 14px;
            border-radius: 50%;
            background: var(--warning-color);
            animation: pulse 1.5s infinite ease-in-out;
        }

        .status-indicator .dot.connected {
            background: var(--success-color);
        }
        .status-indicator .dot.disconnected {
            background: var(--danger-color);
        }
        .status-indicator .dot.warning { /* For paused state */
            background: var(--warning-color);
        }

        @keyframes pulse {
            0% { transform: scale(1); opacity: 1; }
            50% { transform: scale(0.9); opacity: 0.8; }
            100% { transform: scale(1); opacity: 1; }
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 25px;
            margin-top: 30px;
        }

        .card {
            background: var(--card-background);
            border-radius: 16px;
            padding: 25px;
            box-shadow: 0 8px 25px var(--shadow-color);
            transition: transform 0.3s ease-out, box-shadow 0.3s ease-out;
            text-align: left;
            border: 1px solid var(--border-color);
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.12);
        }

        .card h2 {
            color: var(--primary-color);
            margin-bottom: 20px;
            font-size: 1.35em;
            font-weight: 700;
            padding-bottom: 12px;
            border-bottom: 2px solid #f0f0f0;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .card h2 i {
            font-size: 1.1em;
            color: var(--text-accent);
        }

        .info-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 14px 0;
            border-bottom: 1px solid #f5f5f5;
            font-size: 1.05em;
        }

        .info-row:last-child {
            border-bottom: none;
        }

        .info-row span:first-child {
            font-weight: 600;
            color: var(--text-secondary);
            flex-basis: 40%;
        }

        .info-row span:last-child {
            font-family: 'Roboto Mono', monospace;
            color: var(--text-primary);
            font-weight: 700;
            flex-basis: 60%;
            text-align: right;
            word-break: break-all;
        }

        .badge {
            display: inline-block;
            padding: 6px 14px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 700;
            color: white;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .mode-badge { background: var(--secondary-color); }
        .nr-badge { background: var(--warning-color); }

        .signal-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 15px;
            margin-top: 10px;
        }

        .signal-item {
            text-align: center;
            padding: 20px 15px;
            background: #f9fbfd;
            border-radius: 12px;
            border: 1px solid #e8eff5;
            transition: all 0.3s ease-out;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
        }

        .signal-item:hover {
            border-color: var(--primary-color);
            background: #eef5ff;
        }

        .signal-label {
            font-size: 0.9em;
            color: var(--text-secondary);
            margin-bottom: 8px;
            font-weight: 600;
        }

        .signal-value {
            font-size: clamp(1.8rem, 5vw, 2.4rem);
            font-weight: 700;
            font-family: 'Roboto Mono', monospace;
            line-height: 1.1;
        }

        .signal-unit {
            font-size: 0.8em;
            color: #999;
            margin-top: 5px;
        }

        .controls {
            margin-top: 40px;
            display: flex;
            justify-content: center;
            gap: 15px;
            flex-wrap: wrap;
        }

        .btn {
            font-size: 1.1em;
            font-weight: 600;
            padding: 12px 25px;
            border-radius: 10px;
            cursor: pointer;
            transition: background 0.3s ease, transform 0.2s ease;
            border: none;
            outline: none;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            box-shadow: 0 4px 10px rgba(0,0,0,0.07);
        }

        .btn:hover {
            transform: translateY(-2px);
        }

        .btn-primary {
            background: var(--primary-color);
            color: white;
        }
        .btn-primary:hover {
            background: #357ABD;
        }

        .btn-danger {
            background: var(--danger-color);
            color: white;
        }
        .btn-danger:hover {
            background: #D32F2F;
        }
        
        .refresh-controls {
            margin-top: 25px;
            margin-bottom: 30px;
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 12px;
            flex-wrap: wrap;
            font-size: 0.95em;
            color: var(--text-secondary);
        }

        .refresh-controls label {
            font-weight: 600;
        }

        .refresh-controls select,
        .refresh-controls button {
            padding: 10px 15px;
            border-radius: 8px;
            border: 1px solid var(--border-color);
            background-color: var(--card-background);
            cursor: pointer;
            font-size: inherit;
            transition: all 0.3s ease;
        }
        .refresh-controls select:hover,
        .refresh-controls button:hover {
             border-color: var(--primary-color);
        }
        .refresh-controls .refresh-timer-display {
            font-weight: 600;
            color: var(--primary-color);
            min-width: 35px;
            text-align: center;
            display: inline-block;
            padding: 8px 10px;
            background-color: #f0f7ff;
            border: 1px solid #d6eaff;
            border-radius: 8px;
        }
        
        .refresh-controls .btn-toggle-auto {
            background: var(--primary-color);
            color: white;
            padding: 10px 20px;
            font-size: 0.95em;
            display: inline-flex;
            align-items: center;
            gap: 8px;
        }
        .refresh-controls .btn-toggle-auto:hover {
             background: #357ABD;
        }

        .back-link {
            position: absolute;
            top: 20px;
            right: 20px;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: rgba(255, 255, 255, 0.6);
            padding: 10px 18px;
            border-radius: 30px;
            backdrop-filter: blur(8px);
            text-decoration: none;
            font-weight: 600;
            transition: background 0.3s ease;
        }

        .back-link:hover {
            background: rgba(255, 255, 255, 0.8);
        }

        .back-link i {
            color: var(--primary-color);
        }

        /* --- Media Queries for Responsiveness --- */
        @media (max-width: 768px) {
            body { padding: 10px; }
            .container { padding: 0 10px; }
            header h1 { font-size: 2.2rem; }
            .status-indicator { font-size: 1em; padding: 8px 16px; gap: 8px; flex-direction: column; align-items: center; }
            .status-indicator .dot { width: 12px; height: 12px; }
            .grid { grid-template-columns: 1fr; }
            .card { padding: 20px; }
            .card h2 { font-size: 1.25em; padding-bottom: 10px; }
            .info-row { padding: 12px 0; font-size: 1em; }
            .signal-grid { grid-template-columns: 1fr; }
            .signal-value { font-size: 2rem; }
            .controls { flex-direction: column; align-items: center; }
            .btn { width: 80%; max-width: 300px; }
            .refresh-controls { flex-direction: column; align-items: center; width: 100%; }
            .refresh-controls select, .refresh-controls button { width: 80%; max-width: 250px; text-align: center; }
            .refresh-controls .refresh-timer-display { margin-top: 5px; margin-bottom: 5px; }
            .back-link { position: static; margin-bottom: 20px; display: block; width: fit-content; margin: 0 auto 20px auto; }
        }

        @media (max-width: 480px) {
            header h1 { font-size: 1.8rem; }
            .status-indicator { font-size: 0.95em; padding: 8px 12px; }
            .card h2 { font-size: 1.15em; }
            .info-row span:first-child { flex-basis: 50%; }
            .info-row span:last-child { flex-basis: 50%; }
            .signal-value { font-size: 1.8rem; }
            .btn { font-size: 1em; padding: 10px 20px; width: 90%; }
            .refresh-controls select, .refresh-controls button { width: 90%; }
        }
    </style>
</head>
<body>
    <div class="container">
        <a href="/" class="back-link">
            <i class="fas fa-home"></i> OpenWrt Home
        </a>

        <header>
            <h1><i class="fas fa-signal"></i> Sierra Wireless EM9190 Monitor</h1>
            <div class="status-indicator">
                <span class="dot" id="status-dot"></span>
                <span id="status-text">Đang tải dữ liệu...</span>
                <span id="wan-ip-display"></span>
            </div>
        </header>

        <div class="grid">
            <div class="card">
                <h2><i class="fas fa-mobile-alt"></i> Thông tin Modem</h2>
                <div class="info-row"><span>Model:</span><span id="modem">-</span></div>
                <div class="info-row"><span>Firmware:</span><span id="firmware">-</span></div>
                <div class="info-row"><span>Nhiệt độ:</span><span id="temperature">-</span></div>
                <div class="info-row"><span>Chế độ:</span><span id="mode" class="badge mode-badge">-</span></div>
            </div>

            <div class="card">
                <h2><i class="fas fa-broadcast-tower"></i> Băng tần</h2>
                <div class="info-row"><span>Primary LTE:</span><span id="primary_band">-</span></div>
                <div class="info-row"><span>Secondary LTE:</span><span id="secondary_band">-</span></div>
                <div class="info-row"><span>5G NR:</span><span id="nr5g_band" class="badge nr-badge">-</span></div>
            </div>

            <div class="card">
                <h2><i class="fas fa-chart-line"></i> Chất lượng tín hiệu</h2>
                <div class="signal-grid">
                    <div class="signal-item">
                        <div class="signal-label">RSSI</div>
                        <div class="signal-value" id="rssi">-</div>
                        <div class="signal-unit">dBm</div>
                    </div>
                    <div class="signal-item">
                        <div class="signal-label">RSRP</div>
                        <div class="signal-value" id="rsrp">-</div>
                        <div class="signal-unit">dBm</div>
                    </div>
                    <div class="signal-item">
                        <div class="signal-label">RSRQ</div>
                        <div class="signal-value" id="rsrq">-</div>
                        <div class="signal-unit">dB</div>
                    </div>
                    <div class="signal-item">
                        <div class="signal-label">SINR</div>
                        <div class="signal-value" id="sinr">-</div>
                        <div class="signal-unit">dB</div>
                    </div>
                </div>
            </div>

            <div class="card">
                <h2><i class="fas fa-map-marker-alt"></i> Thông tin Cell</h2>
                <div class="info-row"><span>TAC (Hex):</span><span id="tac_hex">-</span></div>
                <div class="info-row"><span>TAC (Dec):</span><span id="tac_dec">-</span></div>
                <div class="info-row"><span>Cập nhật:</span><span id="timestamp">-</span></div>
            </div>
        </div>

        <div class="controls">
            <button class="btn btn-primary" onclick="refreshData()">
                <i class="fas fa-sync-alt"></i> Làm mới thủ công
            </button>
            <button class="btn btn-danger" onclick="resetModem()">
                <i class="fas fa-power-off"></i> Reset Modem
            </button>
        </div>
        
        <div class="refresh-controls">
            <label for="refresh-interval">Tự động làm mới sau:</label>
            <select id="refresh-interval">
                <option value="5000">5 Giây</option>
                <option value="10000">10 Giây</option>
                <option value="15000">15 Giây</option>
                <option value="30000">30 Giây</option>
                <option value="60000">60 Giây</option>
            </select>
            <span class="refresh-timer-display" id="refresh-timer">5s</span>
            <button class="btn btn-toggle-auto" onclick="toggleAutoRefresh()">
                <i class="fas fa-pause" id="auto-refresh-icon"></i> Tắt Tự động
            </button>
        </div>

    </div>

    <script>
        class EM9190Monitor {
            constructor() {
                this.defaultUpdateInterval = 5000; // Default to 5 seconds
                this.updateInterval = this.defaultUpdateInterval; // Current active interval
                this.autoRefreshEnabled = true; // Start with auto-refresh enabled
                this.refreshTimer = null; // Holds the interval timer ID for data fetches
                this.countdownTimer = null; // Holds the countdown interval ID for display

                this.statusDot = document.getElementById('status-dot');
                this.statusText = document.getElementById('status-text');
                this.wanIpDisplay = document.getElementById('wan-ip-display');
                this.refreshIntervalSelect = document.getElementById('refresh-interval');
                this.refreshTimerDisplay = document.getElementById('refresh-timer');
                this.autoRefreshToggleButton = document.getElementById('auto-refresh-icon').closest('button');

                // Set the initial value of the select box based on the default interval
                this.refreshIntervalSelect.value = this.updateInterval;

                this.init();
            }

            init() {
                this.updateCountdownDisplay(this.updateInterval / 1000);
                this.updateAutoRefreshButtonState(this.autoRefreshEnabled);
                
                this.refreshIntervalSelect.addEventListener('change', (e) => {
                    this.setNewUpdateInterval(parseInt(e.target.value, 10));
                });

                this.updateData();
                this.startAutoRefresh();
            }

            async updateData() {
                const currentStatusText = this.statusText.textContent; // Store current status
                this.setConnectionStatus(null, '-'); // Set to a neutral "loading" state
                this.statusText.textContent = 'Đang tải...';

                try {
                    const infoResponse = await fetch('/api.cgi?action=info');
                    if (!infoResponse.ok) {
                        throw new Error(`HTTP error! status: ${infoResponse.status}`);
                    }
                    const infoData = await infoResponse.json();

                    if (infoData.error) {
                        throw new Error(infoData.message || 'Unknown API error for info');
                    }
                    this.updateUI(infoData);

                    const statusResponse = await fetch('/api.cgi?action=status');
                    if (!statusResponse.ok) {
                        throw new Error(`HTTP error! status: ${statusResponse.status}`);
                    }
                    const statusData = await statusResponse.json();

                    if (statusData.error) {
                        throw new Error(statusData.message || 'Unknown API error for status');
                    }
                    // Determine connection status based on device_path from infoData
                    const deviceStatus = infoData.device_path ? 'connected' : 'disconnected';
                    this.setConnectionStatus(deviceStatus === 'connected', statusData.wan_ip);

                    this.resetRefreshTimer();

                } catch (error) {
                    console.error('Error fetching data:', error);
                    // If an error occurs, update status to disconnected and show error message
                    this.setConnectionStatus(false, '-');
                    this.statusText.textContent = 'Lỗi tải dữ liệu';
                    this.resetRefreshTimer(); // Reset timer even on error to keep trying
                }
            }

            updateUI(data) {
                document.getElementById('modem').textContent = data.modem || '-';
                document.getElementById('firmware').textContent = data.firmware || '-';
                document.getElementById('temperature').textContent = data.temperature ? `${data.temperature}°C` : '-';
                document.getElementById('timestamp').textContent = data.timestamp || '-';

                const modeElement = document.getElementById('mode');
                modeElement.textContent = data.mode || '-';
                modeElement.className = 'badge mode-badge'; // Reset classes
                if (data.mode) {
                    if (data.mode.includes('5G')) {
                        modeElement.style.backgroundColor = 'var(--warning-color)'; // Orange for 5G
                    } else if (data.mode.includes('LTE')) {
                        modeElement.style.backgroundColor = '#38b2ac'; // Teal for LTE
                    } else {
                        modeElement.style.backgroundColor = '#48bb78'; // Green for other/unknown
                    }
                } else {
                     modeElement.style.backgroundColor = '#ccc'; // Grey if no mode
                }

                document.getElementById('primary_band').textContent = data.primary_band || '-';
                document.getElementById('secondary_band').textContent = data.secondary_band || '-';

                const nr5gElement = document.getElementById('nr5g_band');
                nr5gElement.textContent = data.nr5g_band || '-';
                if (data.nr5g_band && data.nr5g_band !== '-') {
                    nr5gElement.classList.add('nr-badge');
                } else {
                    nr5gElement.classList.remove('nr-badge');
                }

                this.updateSignalValue('rssi', data.signal.rssi);
                this.updateSignalValue('rsrp', data.signal.rsrp);
                this.updateSignalValue('rsrq', data.signal.rsrq);
                this.updateSignalValue('sinr', data.signal.sinr);

                document.getElementById('tac_hex').textContent = data.tac_hex || '-';
                document.getElementById('tac_dec').textContent = data.tac_dec || '-';
            }

            updateSignalValue(id, value) {
                const element = document.getElementById(id);
                element.textContent = value !== undefined && value !== null ? value : '-';

                if (value === '-' || value === undefined || value === null) {
                    element.style.color = '#ccc';
                    return;
                }

                const numValue = parseFloat(value);
                let color = '#333'; // Default color

                // Apply color coding based on signal strength metrics
                switch (id) {
                    case 'rssi':
                        if (numValue > -70) color = 'var(--success-color)'; // Good
                        else if (numValue > -85) color = 'var(--warning-color)'; // Fair
                        else color = 'var(--danger-color)'; // Poor
                        break;
                    case 'rsrp':
                        if (numValue >= -80) color = 'var(--success-color)'; // Good
                        else if (numValue >= -100) color = 'var(--warning-color)'; // Fair
                        else color = 'var(--danger-color)'; // Poor
                        break;
                    case 'rsrq':
                        if (numValue >= -10) color = 'var(--success-color)'; // Good
                        else if (numValue >= -15) color = 'var(--warning-color)'; // Fair
                        else color = 'var(--danger-color)'; // Poor
                        break;
                    case 'sinr':
                        if (numValue >= 20) color = 'var(--success-color)'; // Excellent
                        else if (numValue >= 10) color = 'var(--warning-color)'; // Good
                        else color = 'var(--danger-color)'; // Poor/Fair
                        break;
                }
                element.style.color = color;
            }

            setConnectionStatus(connected, wanIp) {
                if (connected === null) { // Loading state
                    this.statusText.textContent = 'Đang tải...';
                    this.statusDot.classList.remove('connected', 'disconnected', 'warning');
                    this.wanIpDisplay.textContent = '';
                    this.wanIpDisplay.style.display = 'none';
                } else if (connected) {
                    this.statusText.textContent = 'Đã kết nối';
                    this.statusDot.classList.remove('disconnected', 'warning');
                    this.statusDot.classList.add('connected');
                    if (wanIp && wanIp !== '-') {
                         this.wanIpDisplay.textContent = `(${wanIp})`;
                         this.wanIpDisplay.style.display = 'inline';
                    } else {
                         this.wanIpDisplay.textContent = '';
                         this.wanIpDisplay.style.display = 'none';
                    }
                } else {
                    this.statusText.textContent = 'Mất kết nối';
                    this.statusDot.classList.remove('connected', 'warning');
                    this.statusDot.classList.add('disconnected');
                    this.wanIpDisplay.textContent = '';
                    this.wanIpDisplay.style.display = 'none';
                }
            }

            startAutoRefresh() {
                if (!this.autoRefreshEnabled) return;
                this.stopTimers();
                this.refreshTimer = setInterval(() => {
                    this.updateData();
                }, this.updateInterval);
                this.startCountdown();
            }

            stopTimers() {
                clearInterval(this.refreshTimer);
                clearInterval(this.countdownTimer);
                this.refreshTimer = null;
                this.countdownTimer = null;
            }
            
            resetRefreshTimer() {
                this.stopTimers();
                if (this.autoRefreshEnabled) {
                    this.startCountdown();
                    // Re-schedule the next fetch after the interval
                    this.refreshTimer = setInterval(() => {
                        this.updateData();
                    }, this.updateInterval);
                }
            }

            startCountdown() {
                if (!this.autoRefreshEnabled) return;

                let secondsRemaining = this.updateInterval / 1000;
                this.updateCountdownDisplay(secondsRemaining);

                this.countdownTimer = setInterval(() => {
                    secondsRemaining--;
                    this.updateCountdownDisplay(secondsRemaining);

                    if (secondsRemaining <= 0) {
                        // When countdown finishes, trigger data update and restart timers
                        this.updateData();
                        this.stopTimers(); // Stop current timers
                        if (this.autoRefreshEnabled) { // If still enabled, start new cycle
                            this.startAutoRefresh();
                        }
                    }
                }, 1000);
            }

            updateCountdownDisplay(seconds) {
                this.refreshTimerDisplay.textContent = `${seconds}s`;
            }

            setNewUpdateInterval(interval) {
                this.updateInterval = interval;
                this.updateCountdownDisplay(this.updateInterval / 1000);
                if (this.autoRefreshEnabled) {
                    this.startAutoRefresh(); // Restart interval with new setting
                }
            }

            toggleAutoRefresh() {
                this.autoRefreshEnabled = !this.autoRefreshEnabled;
                this.updateAutoRefreshButtonState(this.autoRefreshEnabled);

                if (this.autoRefreshEnabled) {
                    this.startAutoRefresh();
                    // Attempt to restore previous connection status if it was paused
                    const currentStatusText = this.statusText.textContent;
                    if(currentStatusText === 'Tự động làm mới đã dừng' || currentStatusText === 'Lỗi tải dữ liệu') {
                       // Re-fetch to get correct status or set a general loading state
                       this.setConnectionStatus(null, '-'); // Back to loading state
                       this.statusText.textContent = 'Đang tải...';
                    } else {
                       // Re-apply previous status if it was connected/disconnected
                       const isConnected = this.statusDot.classList.contains('connected');
                       const currentWanIp = this.wanIpDisplay.textContent.replace(/[()]/g, '');
                       this.setConnectionStatus(isConnected, currentWanIp);
                    }
                } else {
                    this.stopTimers();
                    this.refreshTimerDisplay.textContent = '-'; // Clear countdown display
                    this.statusText.textContent = 'Tự động làm mới đã dừng';
                    this.statusDot.classList.remove('connected', 'disconnected');
                    this.statusDot.classList.add('warning'); // Use warning dot for paused state
                    this.wanIpDisplay.textContent = '';
                    this.wanIpDisplay.style.display = 'none';
                }
            }
            
            updateAutoRefreshButtonState(enabled) {
                const icon = this.autoRefreshToggleButton.querySelector('i');
                if (enabled) {
                    icon.classList.remove('fa-play');
                    icon.classList.add('fa-pause');
                    this.autoRefreshToggleButton.textContent = ' Tắt Tự động';
                } else {
                    icon.classList.remove('fa-pause');
                    icon.classList.add('fa-play');
                    this.autoRefreshToggleButton.textContent = ' Bật Tự động';
                }
            }
        }

        function refreshData() {
            const statusText = document.getElementById('status-text');
            statusText.textContent = 'Đang làm mới...';
            
            window.monitor.updateData().then(() => {
                // updateData handles its own status updates and timer resets on success/failure
            });
        }

        async function resetModem() {
            if (!confirm('Bạn có chắc chắn muốn reset modem? Hành động này sẽ làm gián đoạn kết nối hiện tại.')) {
                return;
            }

            const statusText = document.getElementById('status-text');
            
            statusText.textContent = 'Đang gửi lệnh reset...';
            window.monitor.statusDot.className = 'dot warning'; // Show warning while resetting
            window.monitor.autoRefreshEnabled = false; // Temporarily disable auto-refresh
            window.monitor.stopTimers();
            window.monitor.refreshTimerDisplay.textContent = '-';
            window.monitor.updateAutoRefreshButtonState(false);

            try {
                const response = await fetch('/api.cgi?action=reset');
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const data = await response.json();

                if (data.success) {
                    alert('Lệnh reset đã được gửi. Modem sẽ khởi động lại. Trang sẽ tự động tải lại sau khoảng 25-30 giây.');
                    
                    // Reload the page after a delay to allow modem to restart
                    setTimeout(() => {
                         window.location.reload(); 
                    }, 30000); // 30 seconds delay

                } else {
                    alert('Lỗi khi reset modem: ' + (data.message || 'Lỗi không xác định'));
                    statusText.textContent = 'Reset thất bại';
                    window.monitor.statusDot.className = 'dot disconnected'; // Indicate failure
                    window.monitor.autoRefreshEnabled = false; // Keep disabled
                    window.monitor.updateAutoRefreshButtonState(false);
                }
            } catch (error) {
                alert('Không thể gửi lệnh reset: ' + error.message);
                statusText.textContent = 'Lỗi gửi lệnh';
                window.monitor.statusDot.className = 'dot disconnected'; // Indicate failure
                window.monitor.autoRefreshEnabled = false;
                window.monitor.updateAutoRefreshButtonState(false);
            }
        }

        function toggleAutoRefresh() {
            window.monitor.toggleAutoRefresh();
        }

        document.addEventListener('DOMContentLoaded', () => {
            window.monitor = new EM9190Monitor();
        });
    </script>
EOF

# --- Thiết lập quyền truy cập cho các file ---
echo "🔐 Thiết lập quyền truy cập..."
chmod +x "$INSTALL_DIR/scripts/"*.sh
chmod +x "$WEB_DIR/api.cgi"
chmod 644 "$WEB_DIR/index.html"

# --- Tạo file log cho uhttpd riêng của EM9190 Monitor ---
echo "✍️ Tạo file log..."
touch /var/log/uhttpd_em9190_access.log
touch /var/log/uhttpd_em9190_error.log
# Tạo log file cho script chính
touch "$INSTALL_DIR/logs/em9190_monitor.log"

# --- Cấu hình uhttpd độc lập cho EM9190 Monitor ---
echo "🚀 Cấu hình và khởi động EM9190 Monitor web server trên port $PORT..."

# Tạo file cấu hình UCI cho service
UCI_CONFIG_FILE="/etc/config/em9190-monitor"
# Ensure the file is created with correct permissions for root
> "$UCI_CONFIG_FILE"
echo "config em9190-monitor" >> "$UCI_CONFIG_FILE"
echo "    option port '$PORT'" >> "$UCI_CONFIG_FILE"
echo "    option install_dir '$INSTALL_DIR'" >> "$UCI_CONFIG_FILE"
echo "    option web_dir '$WEB_DIR'" >> "$UCI_CONFIG_FILE"
# Commit changes to UCI configuration system
uci commit em9190-monitor

# Tạo script init cho service
cat > /etc/init.d/em9190-monitor << EOF
#!/bin/sh /etc/rc.common

START=99
STOP=10

USE_PROCD=1
PROG=/usr/sbin/uhttpd

# Get configuration from UCI
CONFIG_FILE="/etc/config/em9190-monitor"
if [ -f "\$CONFIG_FILE" ]; then
    PORT=\$(uci -c "\$CONFIG_FILE" get em9190-monitor.@config[0].port 2>/dev/null || echo $DEFAULT_PORT)
    INSTALL_DIR=\$(uci -c "\$CONFIG_FILE" get em9190-monitor.@config[0].install_dir 2>/dev/null || echo "$DEFAULT_INSTALL_DIR")
    WEB_DIR=\$(uci -c "\$CONFIG_FILE" get em9190-monitor.@config[0].web_dir 2>/dev/null || echo "$DEFAULT_WEB_DIR")
else
    # Fallback to default values if config file is missing
    PORT="$DEFAULT_PORT"
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    WEB_DIR="$DEFAULT_WEB_DIR"
fi

# Check if uhttpd executable exists
if [ ! -x "\$PROG" ]; then
    echo "ERROR: uhttpd not found at \$PROG"
    exit 1
fi

# Custom configuration for this uhttpd instance
# Log files for this instance
UHTTPD_ACCESS_LOG="/var/log/uhttpd_em9190_access.log"
UHTTPD_ERROR_LOG="/var/log/uhttpd_em9190_error.log"

# CGI directory
CGI_BIN_DIR="/cgi-bin"

start_service() {
    procd_open_instance "em9190-monitor" # Use a unique instance name
    procd_set_param command "\$PROG" "-f" "-h" "\$WEB_DIR" "-p" "\$PORT" "-x" "\$CGI_BIN_DIR" "-t" "60" "-l" "\$UHTTPD_ACCESS_LOG" "-e" "\$UHTTPD_ERROR_LOG"
    procd_set_param respawn # Ensure it restarts if it crashes
    procd_set_param stdout_log "3" # Log stdout to syslog
    procd_set_param stderr_log "2" # Log stderr to syslog
    procd_close_instance
}

stop_service() {
    # procd_stop_instance "em9190-monitor" # Use the instance name for stopping
    # The above is preferred if using procd_open_instance correctly.
    # If procd_open_instance failed or needs manual stop:
    local PID=$(pgrep -f "\/usr\/sbin\/uhttpd.*-h $WEB_DIR -p $PORT")
    if [ -n "$PID" ]; then
        kill "$PID"
    fi
}

# Reload is not strictly necessary if the config file itself doesn't change,
# but if we were to dynamically reload config, this would be useful.
# For this script, restarting is cleaner.
reload_service() {
    stop_service
    start_service
}
EOF

# Cấp quyền thực thi cho script init
chmod +x /etc/init.d/em9190-monitor

# Kích hoạt và khởi động service
if [ -f /etc/init.d/em9190-monitor ]; then
    /etc/init.d/em9190-monitor enable
    /etc/init.d/em9190-monitor start
else
    echo "ERROR: Failed to create /etc/init.d/em9190-monitor script."
    exit 1
fi

# --- Thông báo hoàn thành cài đặt ---
echo ""
echo "✅ Cài đặt EM9190 Monitor hoàn tất thành công!"

# Lấy địa chỉ IP của interface LAN để hiển thị thông tin truy cập
# Attempt to get LAN IP from network config, fallback to common defaults
LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null)
if [ -z "$LAN_IP" ]; then
    LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1") # Common default
fi
if [ -z "$LAN_IP" ]; then
    LAN_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1) # Last resort
fi
if [ -z "$LAN_IP" ]; then
    LAN_IP="192.168.1.1" # Final fallback
fi

echo ""
echo "🌐 Truy cập EM9190 Monitor tại:"
echo "   => http://$LAN_IP:$PORT"
echo ""
echo "🔗 Giao diện OpenWrt gốc vẫn hoạt động bình thường (nếu có) tại:"
echo "   => http://$LAN_IP (Port 80)"
echo ""
echo "📂 Các file quan trọng:"
echo "   - Web UI & API: $WEB_DIR/"
echo "   - Scripts:      $INSTALL_DIR/scripts/"
echo "   - Logs:         /var/log/uhttpd_em9190_*.log, $INSTALL_DIR/logs/em9190_monitor.log"
echo ""
echo "📜 Các lệnh quản lý Service:"
echo "   - Start:   /etc/init.d/em9190-monitor start"
echo "   - Stop:    /etc/init.d/em9190-monitor stop"
echo "   - Restart: /etc/init.d/em9190-monitor restart"
echo "   - Status:  /etc/init.d/em9190-monitor status"
echo ""
echo "Thoát khỏi chế độ cài đặt."
