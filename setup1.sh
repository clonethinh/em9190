#!/bin/sh

# ==============================================================================
# Script tự động thiết lập màn hình giám sát modem Sierra Wireless EM9190
# Chạy trên OpenWrt/LEDE.
#
# Chức năng:
# 1. Tạo thư mục /usr/bin/em9190_monitor để chứa các script và file HTML.
# 2. Tạo script `get_em9190_status.sh` để lấy thông tin modem (dữ liệu JSON).
# 3. Tạo file `em9190_status.html` để hiển thị thông tin theo dạng bảng trên web.
# 4. Cấu hình uhttpd để phục vụ các file này trên port 9999.
# 5. Khởi động lại uhttpd để áp dụng cấu hình.
#
# Cách sử dụng:
# 1. Đảm bảo router của bạn đã cài đặt 'gcom' hoặc 'sms_tool'.
#    (opkg update && opkg install gcom) HOẶC (opkg update && opkg install sms_tool)
# 2. Lưu nội dung này vào một file (ví dụ: setup_em9190_monitor.sh).
# 3. Gán quyền thực thi: chmod +x setup_em9190_monitor.sh
# 4. Chạy script: ./setup_em9190_monitor.sh
#
# Sau khi chạy thành công, truy cập vào http://<IP_CỦA_ROUTER>:9999/
# (Ví dụ: http://192.168.1.1:9999/)
# ==============================================================================

# --- Cấu hình ---
MONITOR_DIR="/usr/bin/em9190_monitor"
STATUS_SCRIPT_NAME="get_em9190_status.sh"
INDEX_HTML_NAME="em9190_status.html"
STATUS_SCRIPT="${MONITOR_DIR}/${STATUS_SCRIPT_NAME}"
INDEX_HTML="${MONITOR_DIR}/${INDEX_HTML_NAME}"
UHTTPD_CONFIG_SECTION="em9190_monitor"
UHTTPD_PORT="9999"

# Đường dẫn đến các script phụ trợ của 3ginfo-lite (nếu có, ví dụ detect.sh, mccmnc.dat)
RES="/usr/share/3ginfo-lite" 

echo ">>> Bắt đầu thiết lập màn hình giám sát EM9190..."

# --- 1. Tạo thư mục ---
echo ">>> Tạo thư mục: ${MONITOR_DIR}"
mkdir -p "${MONITOR_DIR}"
if [ $? -ne 0 ]; then
    echo "!!! Lỗi: Không thể tạo thư mục ${MONITOR_DIR}. Hãy kiểm tra quyền hoặc dung lượng đĩa. Thoát."
    exit 1
fi

# --- 2. Tạo script lấy thông tin modem (get_em9190_status.sh) ---
echo ">>> Tạo script lấy thông tin modem: ${STATUS_SCRIPT}"
cat << 'EOF_STATUS_SCRIPT' > "${STATUS_SCRIPT}"
#!/bin/sh

# Script để lấy trạng thái modem EM9190 và xuất ra JSON.
# Cần 'gcom' hoặc 'sms_tool' để giao tiếp với modem.

# --- Khai báo biến ---
RES="/usr/share/3ginfo-lite" # Đường dẫn đến các script phụ trợ, nếu có

# --- Hàm định nghĩa băng tần 4G ---
band4g() {
	echo -n "B${1}"
	case "${1}" in
		"1") echo -n " (2100 MHz)";; "2") echo -n " (1900 MHz)";; "3") echo -n " (1800 MHz)";; "4") echo -n " (1700 MHz)";; "5") echo -n " (850 MHz)";; "7") echo -n " (2600 MHz)";; "8") echo -n " (900 MHz)";; "11") echo -n " (1500 MHz)";; "12") echo -n " (700 MHz)";; "13") echo -n " (700 MHz)";; "14") echo -n " (700 MHz)";; "17") echo -n " (700 MHz)";; "18") echo -n " (850 MHz)";; "19") echo -n " (850 MHz)";; "20") echo -n " (800 MHz)";; "21") echo -n " (1500 MHz)";; "24") echo -n " (1600 MHz)";; "25") echo -n " (1900 MHz)";; "26") echo -n " (850 MHz)";; "28") echo -n " (700 MHz)";; "29") echo -n " (700 MHz)";; "30") echo -n " (2300 MHz)";; "31") echo -n " (450 MHz)";; "32") echo -n " (1500 MHz)";; "34") echo -n " (2000 MHz)";; "37") echo -n " (1900 MHz)";; "38") echo -n " (2600 MHz)";; "39") echo -n " (1900 MHz)";; "40") echo -n " (2300 MHz)";; "41") echo -n " (2500 MHz)";; "42") echo -n " (3500 MHz)";; "43") echo -n " (3700 MHz)";; "46") echo -n " (5200 MHz)";; "47") echo -n " (5900 MHz)";; "48") echo -n " (3500 MHz)";; "50") echo -n " (1500 MHz)";; "51") echo -n " (1500 MHz)";; "53") echo -n " (2400 MHz)";; "54") echo -n " (1600 MHz)";; "65") echo -n " (2100 MHz)";; "66") echo -n " (1700 MHz)";; "67") echo -n " (700 MHz)";; "69") echo -n " (2600 MHz)";; "70") echo -n " (1700 MHz)";; "71") echo -n " (600 MHz)";; "72") echo -n " (450 MHz)";; "73") echo -n " (450 MHz)";; "74") echo -n " (1500 MHz)";; "75") echo -n " (1500 MHz)";; "76") echo -n " (1500 MHz)";; "85") echo -n " (700 MHz)";; "87") echo -n " (410 MHz)";; "88") echo -n " (410 MHz)";; "103") echo -n " (700 MHz)";; "106") echo -n " (900 MHz)";; "*") echo -n "";;
	esac
}

# --- Hàm định nghĩa băng tần 5G ---
band5g() {
	echo -n "n${1}"
	case "${1}" in
		"1") echo -n " (2100 MHz)";; "2") echo -n " (1900 MHz)";; "3") echo -n " (1800 MHz)";; "5") echo -n " (850 MHz)";; "7") echo -n " (2600 MHz)";; "8") echo -n " (900 MHz)";; "12") echo -n " (700 MHz)";; "13") echo -n " (700 MHz)";; "14") echo -n " (700 MHz)";; "18") echo -n " (850 MHz)";; "20") echo -n " (800 MHz)";; "24") echo -n " (1600 MHz)";; "25") echo -n " (1900 MHz)";; "26") echo -n " (850 MHz)";; "28") echo -n " (700 MHz)";; "29") echo -n " (700 MHz)";; "30") echo -n " (2300 MHz)";; "34") echo -n " (2100 MHz)";; "38") echo -n " (2600 MHz)";; "39") echo -n " (1900 MHz)";; "40") echo -n " (2300 MHz)";; "41") echo -n " (2500 MHz)";; "46") echo -n " (5200 MHz)";; "47") echo -n " (5900 MHz)";; "48") echo -n " (3500 MHz)";; "50") echo -n " (1500 MHz)";; "51") echo -n " (1500 MHz)";; "53") echo -n " (2400 MHz)";; "54") echo -n " (1600 MHz)";; "65") echo -n " (2100 MHz)";; "66") echo -n " (1700/2100 MHz)";; "67") echo -n " (700 MHz)";; "70") echo -n " (2000 MHz)";; "71") echo -n " (600 MHz)";; "74") echo -n " (1500 MHz)";; "75") echo -n " (1500 MHz)";; "76") echo -n " (1500 MHz)";; "77") echo -n " (3700 MHz)";; "78") echo -n " (3500 MHz)";; "79") echo -n " (4700 MHz)";; "80") echo -n " (1800 MHz)";; "81") echo -n " (900 MHz)";; "82") echo -n " (800 MHz)";; "83") echo -n " (700 MHz)";; "84") echo -n " (2100 MHz)";; "85") echo -n " (700 MHz)";; "86") echo -n " (1700 MHz)";; "89") echo -n " (850 MHz)";; "90") echo -n " (2500 MHz)";; "91") echo -n " (800/1500 MHz)";; "92") echo -n " (800/1500 MHz)";; "93") echo -n " (900/1500 MHz)";; "94") echo -n " (900/1500 MHz)";; "95") echo -n " (2100 MHz)";; "96") echo -n " (6000 MHz)";; "97") echo -n " (2300 MHz)";; "98") echo -n " (1900 MHz)";; "99") echo -n " (1600 MHz)";; "100") echo -n " (900 MHz)";; "101") echo -n " (1900 MHz)";; "102") echo -n " (6200 MHz)";; "104") echo -n " (6700 MHz)";; "105") echo -n " (600 MHz)";; "106") echo -n " (900 MHz)";; "109") echo -n " (700/1500 MHz)";; "257") echo -n " (28 GHz)";; "258") echo -n " (26 GHz)";; "259") echo -n " (41 GHz)";; "260") echo -n " (39 GHz)";; "261") echo -n " (28 GHz)";; "262") echo -n " (47 GHz)";; "263") echo -n " (60 GHz)";; "*") echo -n "";;
	esac
}

# --- Hàm tìm thiết bị modem ---
# Sử dụng logic từ detect.sh để tìm cổng serial của modem
detect_modem_device() {
    local DEVICE=""
    
    # Try from modemdefine config
    local CONFIG="modemdefine"
    local MODEMZ=$(uci show \$CONFIG 2>/dev/null | grep -o "@modemdefine\[[0-9]*\]\.modem" | wc -l | xargs)
    if [ -n "\$MODEMZ" ]; then
        if [[ \$MODEMZ = 0 ]]; then
            DEVICE=\$(uci -q get 3ginfo.@3ginfo[0].device)
            if [ -n "\$DEVICE" ]; then echo "\$DEVICE"; return 0; fi
        fi
        if [[ \$MODEMZ = 1 ]]; then
            DEVICE=\$(uci -q get modemdefine.@modemdefine[0].comm_port)
            if [ -n "\$DEVICE" ]; then echo "\$DEVICE"; return 0; fi
        fi
        if [[ \$MODEMZ > 1 ]]; then
            DEVICE=\$(uci -q get modemdefine.@general[0].main_modem)
            if [ -n "\$DEVICE" ]; then echo "\$DEVICE"; return 0; fi
        fi
    fi

    # Try from 3ginfo config
    DEVICE=\$(uci -q get 3ginfo.@3ginfo[0].device)
    if [ -n "\$DEVICE" ]; then echo "\$DEVICE"; return 0; fi

    # Try from temporary config file
    local MODEMFILE="/tmp/modem"
    if [ -e "\$MODEMFILE" ]; then
        DEVICE=\$(cat "\$MODEMFILE")
        if [ -n "\$DEVICE" ]; then echo "\$DEVICE"; return 0; fi
    fi

    # Fallback: Find any device that responds to AT commands
    # This part requires gcom or sms_tool to be installed
    local DEVICES=\$(find /dev -name "ttyUSB*" -o -name "ttyACM*" -o -name "wwan*at*" | sort -r)
    for DEV in \$DEVICES; do
        if [ -x "/usr/bin/gcom" ]; then
            /usr/bin/gcom -d "\$DEV" -s /usr/share/3ginfo-lite/check.gcom >/dev/null 2>&1
            if [ \$? = 0 ]; then
                echo "\$DEV" | tee "\$MODEMFILE"
                return 0
            fi
        elif [ -x "/usr/bin/sms_tool" ]; then
            # sms_tool doesn't have a direct "check.gcom" equivalent.
            # We can try a simple AT command that should always work.
            /usr/bin/sms_tool -d "\$DEV" at "AT" >/dev/null 2>&1
            if [ \$? = 0 ]; then
                echo "\$DEV" | tee "\$MODEMFILE"
                return 0
            fi
        fi
    done

    echo "" # No device found
    return 1
}

# --- Hàm vệ sinh chuỗi/số cho JSON ---
sanitize_string() {
    [ -z "\$1" ] && echo "-" || echo "\$1" | tr -d '\\r\\n'
}
sanitize_number() {
    [ -z "\$1" ] && echo "-" || echo "\$1"
}

# --- Bắt đầu lấy dữ liệu ---
DEVICE=\$(detect_modem_device)

if [ -z "\$DEVICE" ]; then
    echo '{"error":"No modem device found. Please ensure modem is connected and drivers are loaded."}'
    exit 0
fi

# Biến để lưu trữ toàn bộ output từ các lệnh AT
O=""

# Kiểm tra công cụ AT
AT_TOOL=""
if [ -x "/usr/bin/gcom" ]; then
    AT_TOOL="/usr/bin/gcom"
elif [ -x "/usr/bin/sms_tool" ]; then
    AT_TOOL="/usr/bin/sms_tool"
fi

if [ -z "\$AT_TOOL" ]; then
    echo '{"error":"Required tool (gcom or sms_tool) not found. Please install one."}'
    exit 0
fi

# Gửi một loạt các lệnh AT
O=\$( (
    echo "AT+CGMM"
    echo "AT+CGMR"
    echo "AT!GSTATUS?"
    echo "AT+CSQ"
    echo "AT+CREG?"
    echo "AT+CPIN?"
    echo "AT+GSN"
    echo "AT+CIMI"
    echo "AT+ICCID"
    # Thêm các lệnh AT khác nếu cần để lấy thông tin chi tiết hơn
    # Ví dụ:
    # echo "AT+QCAINFO" # For Quectel CA info
    # echo "AT+QENG=\"servingcell\"" # For Quectel serving cell info
) | "\$AT_TOOL" -d "\$DEVICE" -f - 2>/dev/null )

if [ -z "\$O" ]; then
    echo '{"error":"Failed to get modem response. Device might be busy or invalid."}'
    exit 0
fi

# --- Phân tích dữ liệu ---
MODEL=$(echo "\$O" | sed -n '/^\(AT+CGMM\|ATI\)/,+2p' | awk '/^\s*[^AT]/{print \$0; exit}' | tr -d '\r\n')
FW=$(echo "\$O" | sed -n '/^\(AT+CGMR\|AT+GMR\)/,+2p' | awk '/^\s*[^AT]/{print \$0; exit}' | tr -d '\r\n')

TEMP_RAW=$(echo "\$O" | awk -F: '/Temperature:/ {print \$3}' | tr -d ' \r\n' | xargs)
[ -n "\$TEMP_RAW" ] && TEMP="\$TEMP_RAW °C" || TEMP="-"

MODE_RAW=$(echo "\$O" | awk '/^System mode:/ {print \$3}')
case "\$MODE_RAW" in
    "LTE") MODE="LTE" ;;
    "ENDC") MODE="5G NSA" ;;
    "NR5G") MODE="5G SA" ;;
    *) MODE="Unknown" ;;
esac

TAC_RAW=$(echo "\$O" | awk '/.*TAC:/ {print \$6}' | tr -d '\r\n')
if [ -n "\$TAC_RAW" ]; then
    TAC_DEC=$(printf "%d" "0x\$TAC_RAW")
    TAC_HEX="\$TAC_RAW"
else
    TAC_DEC="-"
    TAC_HEX="-"
fi

# Tín hiệu (GSTATUS? có thể không chi tiết, dùng các giá trị mặc định)
# EM9190 thường có RSSI, RSRP, RSRQ, SINR trên một dòng riêng hoặc gần nhau
RSSI=$(echo "\$O" | awk '/RSSI:/ {print \$2; exit}' | tr -d '\r\n')
RSRP=$(echo "\$O" | awk '/RSRP:/ {print \$2; exit}' | tr -d '\r\n')
RSRQ=$(echo "\$O" | awk '/RSRQ:/ {print \$3; exit}' | tr -d '\r\n')
SINR=$(echo "\$O" | awk '/SINR:/ {print \$3; exit}' | tr -d '\r\n')

# Bands (Primary & Secondary for LTE & 5G)
PBAND="-"; PBAND_MHZ="-"; S1BAND="-"; S1BAND_MHZ="-";
S2BAND="-"; S2BAND_MHZ="-"; S3BAND="-"; S3BAND_MHZ="-";

LTE_BAND_RAW=$(echo "\$O" | awk '/^LTE band:/ {print \$3}')
LTE_BAND_MHZ=$(echo "\$O" | awk '/^LTE band:/ {print \$6}')
if [ -n "\$LTE_BAND_RAW" ]; then
    PBAND="\$(band4g \${LTE_BAND_RAW/B/})"
    [ -n "\$LTE_BAND_MHZ" ] && PBAND_MHZ="@\${LTE_BAND_MHZ} MHz"
    MODE="\${MODE} \${PBAND}\${PBAND_MHZ}"
fi

# SCC1 LTE
LTE_SCC1_STATE=$(echo "\$O" | awk -F: '/^LTE SCC1 state:.*ACTIVE/ {print \$3}')
LTE_SCC1_MHZ=$(echo "\$O" | awk '/^LTE SCC1 bw/ {print \$5}')
if [ -n "\$LTE_SCC1_STATE" ] && [ "\$LTE_SCC1_STATE" != "---" ]; then
    S1BAND="\$(band4g \${LTE_SCC1_STATE/B/})"
    [ -n "\$LTE_SCC1_MHZ" ] && S1BAND_MHZ="@\${LTE_SCC1_MHZ} MHz"
    MODE="\${MODE} + \$(band4g \${LTE_SCC1_STATE/B/})"
fi

# SCC2 LTE
LTE_SCC2_STATE=$(echo "\$O" | awk -F: '/^LTE SCC2 state:.*ACTIVE/ {print \$3}')
LTE_SCC2_MHZ=$(echo "\$O" | awk '/^LTE SCC2 bw/ {print \$5}')
if [ -n "\$LTE_SCC2_STATE" ] && [ "\$LTE_SCC2_STATE" != "---" ]; then
    S2BAND="\$(band4g \${LTE_SCC2_STATE/B/})"
    [ -n "\$LTE_SCC2_MHZ" ] && S2BAND_MHZ="@\${LTE_SCC2_MHZ} MHz"
    MODE="\${MODE} + \$(band4g \${LTE_SCC2_STATE/B/})"
fi

# SCC3 LTE
LTE_SCC3_STATE=$(echo "\$O" | awk -F: '/^LTE SCC3 state:.*ACTIVE/ {print \$3}')
LTE_SCC3_MHZ=$(echo "\$O" | awk '/^LTE SCC3 bw/ {print \$5}')
if [ -n "\$LTE_SCC3_STATE" ] && [ "\$LTE_SCC3_STATE" != "---" ]; then
    S3BAND="\$(band4g \${LTE_SCC3_STATE/B/})"
    [ -n "\$LTE_SCC3_MHZ" ] && S3BAND_MHZ="@\${LTE_SCC3_MHZ} MHz"
    MODE="\${MODE} + \$(band4g \${LTE_SCC3_STATE/B/})"
fi

# 5G NR band
NR5G_BAND_RAW=$(echo "\$O" | awk '/^SCC.*NR5G band:/ {print \$4}' | tr -d '\r\n')
NR5G_BAND_MHZ=$(echo "\$O" | awk '/^SCC.*NR5G bw:/ {print \$8}' | tr -d '\r\n')
if [ -n "\$NR5G_BAND_RAW" ] && [ "\$NR5G_BAND_RAW" != "---" ]; then
    NR5G_BAND="\$(band5g \${NR5G_BAND_RAW/n/})"
    [ -n "\$NR5G_BAND_MHZ" ] && NR5G_BAND_MHZ="@\${NR5G_BAND_MHZ} MHz"
    MODE="\${MODE} + \${NR5G_BAND}\${NR5G_BAND_MHZ}"
fi

# Chuẩn hóa chế độ mạng cuối cùng
MODE=$(echo "\$MODE" | sed 's/LTE-A/LTE-A |/' | sed 's/ + / + /g')

# SIM and Registration Info
REG="-"; SSIM="-"; NR_IMEI="-"; NR_IMSI="-"; NR_ICCID="-";
LAC_DEC="-"; LAC_HEX="-"; CID_DEC="-"; CID_HEX="-";

# CREG
CREG_INFO=$(echo "\$O" | awk -F[,] '/^\+CREG:/ {print \$0}')
if [ -n "\$CREG_INFO" ]; then
    # Use busybox awk for hex conversion if standard awk isn't available on OpenWrt
    eval $(echo "\$CREG_INFO" | busybox awk -F[,] '{gsub(/[[:space:]"]+/,"");printf "T=\"%d\";LAC_HEX=\"%X\";CID_HEX=\"%X\";LAC_DEC=\"%d\";CID_DEC=\"%d\";MODE_NUM=\"%d\"", \$2, "0x"\$3, "0x"\$4, "0x"\$3, "0x"\$4, \$5}')
    case "\$T" in
        0*) REG="Not registered, ME not searching" ;;
        1*) REG="Registered, home network" ;;
        2*) REG="Not registered, but ME is currently trying to attach" ;;
        3*) REG="Registration denied" ;;
        5*) REG="Registered, roaming" ;;
        6*) REG="Registered for URC reporting" ;;
        7*) REG="Registered for NGRC reporting" ;;
        *) REG="Unknown (\$T)" ;;
    esac
fi

# CPIN
CPIN_INFO=$(echo "\$O" | awk -F[:] '/^\+CPIN:/ {print \$2}' | tr -d '\r\n' | xargs)
[ "\$CPIN_INFO" = "READY" ] && SSIM="READY" || SSIM="\$CPIN_INFO"
[ -z "\$SSIM" ] && SSIM="Not available"

# IMEI, IMSI, ICCID
NR_IMEI=$(echo "\$O" | awk -F: '/^\+GSN:/ {print \$2}' | tr -d '\r\n' | xargs)
[ -z "\$NR_IMEI" ] && NR_IMEI=$(echo "\$O" | awk '/IMEI:/ {print \$2}' | tr -d '\r\n' | xargs) # Fallback if GSTATUS provides it
[ -z "\$NR_IMEI" ] && NR_IMEI="-"

NR_IMSI=$(echo "\$O" | awk -F: '/^\+CIMI:/ {print \$2}' | tr -d '\r\n' | xargs)
[ -z "\$NR_IMSI" ] && NR_IMSI="-"

NR_ICCID=$(echo "\$O" | awk -F: '/^\+ICCID:/ {print \$2}' | tr -d '\r\n' | xargs)
[ -z "\$NR_ICCID" ] && NR_ICCID=$(echo "\$O" | awk '/ICCID:/ {print \$2}' | tr -d '\r\n' | xargs) # Fallback if GSTATUS provides it
[ -z "\$NR_ICCID" ] && NR_ICCID="-"

# CSQ
CSQ=$(echo "\$O" | awk -F[,\ ] '/^\+CSQ:/ {print \$2}')
[ "x\$CSQ" = "x" ] && CSQ=-1
if [ \$CSQ -ge 0 -a \$CSQ -le 31 ]; then
	CSQ_PER=\$(( \$CSQ * 100/31 ))
else
	CSQ=""
	CSQ_PER=""
fi

# COPS
COPS=""; COPS_MCC=""; COPS_MNC=""; LOC="-";
COPS_INFO=$(echo "\$O" | awk -F[,] '/^\+COPS:/ {print \$0}')
COPS_NUM=$(echo "\$COPS_INFO" | awk -F\" '/^\+COPS: *,2,/ {print \$2}')
if [ -n "\$COPS_NUM" ]; then
	COPS_MCC=\${COPS_NUM:0:3}
	COPS_MNC=\${COPS_NUM:3:3}
    # Lấy tên nhà mạng và vị trí từ file mccmnc.dat (nếu có)
    if [ -e "\${RES}/mccmnc.dat" ]; then
        COPS_NAME_FROM_FILE=\$(awk -F[\;] '/^\${COPS_NUM};/ {print \$3}' \${RES}/mccmnc.dat | xargs)
        LOC=\$(awk -F[\;] '/^\${COPS_NUM};/ {print \$2}' \${RES}/mccmnc.dat | xargs)
        [ -n "\$COPS_NAME_FROM_FILE" ] && COPS="\$COPS_NAME_FROM_FILE"
    fi
fi
TCOPS_TEXT=$(echo "\$COPS_INFO" | awk -F\" '/^\+COPS: *,0,/ {print \$2}')
[ -n "\$TCOPS_TEXT" ] && COPS="\$TCOPS_TEXT" # Ưu tiên tên dạng text từ modem
[ -z "\$COPS" ] && COPS="\$COPS_NUM" # Fallback nếu tên không có

# --- In JSON Output ---
cat <<EOF
{
"conn_time":"-",
"conn_time_sec":"-",
"conn_time_since":"-",
"rx":"-",
"tx":"-",
"modem":"\$(sanitize_string "\$MODEL")",
"mtemp":"\$(sanitize_string "\$TEMP")",
"firmware":"\$(sanitize_string "\$FW")",
"cport":"\$(sanitize_string "\$DEVICE")",
"protocol":"N/A",
"csq":"\$(sanitize_number "\$CSQ")",
"signal":"\$(sanitize_number "\$CSQ_PER")",
"operator_name":"\$(sanitize_string "\$COPS")",
"operator_mcc":"\$(sanitize_string "\$COPS_MCC")",
"operator_mnc":"\$(sanitize_string "\$COPS_MNC")",
"location":"\$(sanitize_string "\$LOC")",
"mode":"\$(sanitize_string "\$MODE")",
"registration":"\$(sanitize_string "\$REG")",
"simslot":"\$(sanitize_string "\$SSIM")",
"imei":"\$(sanitize_string "\$NR_IMEI")",
"imsi":"\$(sanitize_string "\$NR_IMSI")",
"iccid":"\$(sanitize_string "\$NR_ICCID")",
"lac_dec":"\$(sanitize_number "\$LAC_DEC")",
"lac_hex":"\$(sanitize_string "\$LAC_HEX")",
"tac_dec":"\$(sanitize_number "\$TAC_DEC")",
"tac_hex":"\$(sanitize_string "\$TAC_HEX")",
"tac_h":"-",
"tac_d":"-",
"cid_dec":"\$(sanitize_number "\$CID_DEC")",
"cid_hex":"\$(sanitize_string "\$CID_HEX")",
"pci":"-",
"earfcn":"-",
"pband":"\$(sanitize_string "\$PBAND")\$(sanitize_string "\$PBAND_MHZ")",
"s1band":"\$(sanitize_string "\$S1BAND")\$(sanitize_string "\$S1BAND_MHZ")",
"s1pci":"-",
"s1earfcn":"-",
"s2band":"\$(sanitize_string "\$S2BAND")\$(sanitize_string "\$S2BAND_MHZ")",
"s2pci":"-",
"s2earfcn":"-",
"s3band":"\$(sanitize_string "\$S3BAND")\$(sanitize_string "\$S3BAND_MHZ")",
"s3pci":"-",
"s3earfcn":"-",
"s4band":"-",
"s4pci":"-",
"s4earfcn":"-",
"rsrp":"\$(sanitize_number "\$RSRP")",
"rsrq":"\$(sanitize_number "\$RSRQ")",
"rssi":"\$(sanitize_number "\$RSSI")",
"sinr":"\$(sanitize_number "\$SINR")"
}
EOF
EOF_STATUS_SCRIPT
if [ $? -ne 0 ]; then
    echo "!!! Lỗi: Không thể tạo file ${STATUS_SCRIPT}. Thoát."
    exit 1
fi
chmod +x "${STATUS_SCRIPT}"
if [ $? -ne 0 ]; then
    echo "!!! Lỗi: Không thể gán quyền thực thi cho ${STATUS_SCRIPT}. Thoát."
    exit 1
fi

# --- 3. Tạo file HTML hiển thị (em9190_status.html) ---
echo ">>> Tạo file HTML hiển thị: ${INDEX_HTML}"
cat << 'EOF_HTML' > "${INDEX_HTML}"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EM9190 Modem Status</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f0f2f5; margin: 0; padding: 0; color: #333; line-height: 1.6; }
        .container { max-width: 900px; margin: 30px auto; background-color: #fff; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }
        h1 { color: #007bff; text-align: center; margin-bottom: 25px; font-size: 2.2em; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        td, th { border: 1px solid #e0e0e0; padding: 12px 10px; text-align: left; font-size: 1.1em; }
        th { background-color: #e9ecef; color: #495057; font-weight: 600; }
        tr:nth-child(even) { background-color: #f8f9fa; }
        tr:hover { background-color: #e2e6ea; }
        .key { font-weight: 600; width: 35%; background-color: #f1f3f5; color: #555; }
        .value { width: 65%; word-break: break-word; }
        .error { color: #dc3545; font-weight: bold; text-align: center; }
        .loading { font-style: italic; color: #6c757d; }
        .loading td { text-align: center; padding: 30px; }
        .data-row td { padding: 12px 10px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Sierra Wireless EM9190 Modem Status</h1>
        <table id="statusTable">
            <thead>
                <tr>
                    <th class="key">Parameter</th>
                    <th class="value">Value</th>
                </tr>
            </thead>
            <tbody id="statusTableBody">
                <tr class="loading"><td colspan="2">Loading modem status...</td></tr>
            </tbody>
        </table>
    </div>

    <script>
        function updateStatus() {
            // Sử dụng path tương đối '/get_em9190_status.sh' vì cả hai file nằm trong cùng thư mục gốc của uhttpd
            fetch('/get_em9190_status.sh') 
                .then(response => {
                    if (!response.ok) {
                        throw new Error(`HTTP error! status: ${response.status}`);
                    }
                    return response.json();
                })
                .then(data => {
                    const tableBody = document.getElementById('statusTableBody');
                    tableBody.innerHTML = ''; // Xóa nội dung cũ

                    if (data.error) {
                        tableBody.innerHTML = `<tr><td colspan="2" class="error">${data.error}</td></tr>`;
                        return;
                    }

                    // Định nghĩa thứ tự hiển thị và tên thân thiện
                    const displayOrder = [
                        { id: "modem", name: "Modem Model" },
                        { id: "firmware", name: "Firmware" },
                        { id: "mtemp", name: "Temperature" },
                        { id: "cport", name: "Device Port" },
                        { id: "protocol", name: "Protocol" },
                        { id: "simslot", name: "SIM Status" },
                        { id: "imei", name: "IMEI" },
                        { id: "imsi", name: "IMSI" },
                        { id: "iccid", name: "ICCID" },
                        { id: "csq", name: "Signal (CSQ)" },
                        { id: "signal", name: "Signal (%)" },
                        { id: "operator_name", name: "Operator Name" },
                        { id: "operator_mcc", name: "MCC" },
                        { id: "operator_mnc", name: "MNC" },
                        { id: "location", name: "Location" },
                        { id: "mode", name: "Network Mode" },
                        { id: "registration", name: "Registration" },
                        { id: "tac_dec", name: "TAC (Decimal)" },
                        { id: "tac_hex", name: "TAC (Hex)" },
                        { id: "lac_dec", name: "LAC (Decimal)" },
                        { id: "lac_hex", name: "LAC (Hex)" },
                        { id: "cid_dec", name: "CID (Decimal)" },
                        { id: "cid_hex", name: "CID (Hex)" },
                        { id: "pband", name: "Primary Band" },
                        { id: "rsrp", name: "RSRP (dBm)" },
                        { id: "rsrq", name: "RSRQ (dB)" },
                        { id: "rssi", name: "RSSI (dBm)" },
                        { id: "sinr", name: "SINR (dB)" },
                        { id: "s1band", name: "Secondary Band 1" },
                        { id: "s2band", name: "Secondary Band 2" },
                        { id: "s3band", name: "Secondary Band 3" },
                        // Thêm các trường khác nếu cần thiết và có trong JSON output
                    ];

                    displayOrder.forEach(param => {
                        const value = data[param.id];
                        const displayValue = (value === "" || value === "-" || value === null) ? "-" : value;

                        const tr = document.createElement('tr');
                        tr.className = 'data-row';
                        tr.innerHTML = `
                            <td class="key">${param.name}</td>
                            <td class="value">${displayValue}</td>
                        `;
                        tableBody.appendChild(tr);
                    });
                })
                .catch(error => {
                    const tableBody = document.getElementById('statusTableBody');
                    tableBody.innerHTML = `<tr><td colspan="2" class="error">Failed to load status. Check network, modem connection, or script. Error: ${error}</td></tr>`;
                    console.error('Error fetching status:', error);
                });
        }

        // Cập nhật trạng thái mỗi 15 giây
        updateStatus();
        setInterval(updateStatus, 15000); // 15000 milliseconds = 15 seconds
    </script>
</body>
</html>
EOF_HTML
if [ $? -ne 0 ]; then
    echo "!!! Lỗi: Không thể tạo file ${INDEX_HTML}. Thoát."
    exit 1
fi

# --- 4. Cấu hình uhttpd ---
echo ">>> Cấu hình uhttpd để phục vụ trên port ${UHTTPD_PORT}..."

# Xóa cấu hình cũ nếu tồn tại để tránh trùng lặp hoặc lỗi
uci -q delete uhttpd."${UHTTPD_CONFIG_SECTION}"

# Thêm cấu hình mới
uci add uhttpd "${UHTTPD_CONFIG_SECTION}"
uci set uhttpd."${UHTTPD_CONFIG_SECTION}".enabled='1'
uci set uhttpd."${UHTTPD_CONFIG_SECTION}".listen_port="${UHTTPD_PORT}"
uci set uhttpd."${UHTTPD_CONFIG_SECTION}".home="${MONITOR_DIR}"
uci set uhttpd."${UHTTPD_CONFIG_SECTION}".index="${INDEX_HTML_NAME}"

# Thêm interpreter cho shell script để uhttpd có thể thực thi nó
uci add_list uhttpd."${UHTTPD_CONFIG_SECTION}".interpreter='/usr/bin/sh'
uci add_list uhttpd."${UHTTPD_CONFIG_SECTION}".interpreter='/bin/ash'

uci commit uhttpd
echo ">>> Cấu hình uhttpd đã được thêm/cập nhật."

# --- 5. Khởi động lại uhttpd ---
echo ">>> Khởi động lại dịch vụ uhttpd..."
/etc/init.d/uhttpd restart
if [ $? -ne 0 ]; then
    echo "!!! Lỗi: Không thể khởi động lại uhttpd. Hãy thử thủ công bằng '/etc/init.d/uhttpd restart'."
    echo "!!! Kiểm tra file log của uhttpd để biết thêm chi tiết lỗi."
fi

echo ""
echo ">>> Thiết lập hoàn tất!"
echo ">>> Truy cập màn hình giám sát modem tại:"
echo "    http://$(/sbin/ifconfig br-lan | grep 'inet addr:' | awk '{print $2}' | cut -f2 -d:):${UHTTPD_PORT}/"
echo "    (IP trên là ví dụ, hãy kiểm tra IP thực tế của router nếu không truy cập được)"
echo ""
echo "Lưu ý quan trọng:"
echo " - Đảm bảo modem EM9190 đã được kết nối và nhận dạng bởi hệ thống."
echo " - Đảm bảo bạn đã cài đặt gói 'gcom' HOẶC 'sms_tool' (ví dụ: 'opkg install gcom')."
echo " - Nếu bạn sao chép file này từ Windows, hãy chạy 'dos2unix setup_em9190_monitor.sh' trước khi thực thi."
echo " - Output của các lệnh AT có thể khác nhau tùy theo firmware modem, script có thể cần điều chỉnh."

exit 0
