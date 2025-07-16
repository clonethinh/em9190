#!/bin/sh

# ===================================================================
# Setup Script for EM9190 Monitoring Web Interface
# Port: 8888
# Website Directory: /www/em9190
# ===================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEB_DIR="/www/em9190"
CGI_DIR="/www/em9190/cgi-bin"
PORT="8888"
UHTTPD_CONFIG="/etc/config/uhttpd"

echo "=== Sierra Wireless EM9190 Monitoring Setup ==="
echo "Port: $PORT"
echo "Web Directory: $WEB_DIR"
echo ""

# 1. Tạo thư mục website
echo "Tạo thư mục website..."
mkdir -p "$WEB_DIR"
mkdir -p "$CGI_DIR"

# 2. Tạo file HTML chính
echo "Tạo file HTML chính..."
cat > "$WEB_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="vi">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EM9190 Monitoring</title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500&display=swap');

        :root {
            --primary-color: #6366f1;
            --secondary-color: #8b5cf6;
            --accent-color: #06b6d4;
            --success-color: #10b981;
            --warning-color: #f59e0b;
            --error-color: #ef4444;

            /* Light Mode Variables */
            --light-bg-primary: #f8fafc;
            --light-bg-secondary: #e2e8f0;
            --light-bg-card: #ffffff;
            --light-text-primary: #0f172a;
            --light-text-secondary: #475569;
            --light-text-muted: #64748b;
            --light-border-color: #cbd5e1;
            --light-shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
            --light-shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
            --light-shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05);
            --light-shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);

            /* Dark Mode Variables */
            --dark-bg-primary: #0f172a;
            --dark-bg-secondary: #1e293b;
            --dark-bg-card: #334155;
            --dark-text-primary: #f8fafc;
            --dark-text-secondary: #cbd5e1;
            --dark-text-muted: #94a3b8;
            --dark-border-color: #475569;
            --dark-shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05);
            --dark-shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
            --dark-shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05);
            --dark-shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);

            --shadow-sm: var(--dark-shadow-sm);
            --shadow-md: var(--dark-shadow-md);
            --shadow-lg: var(--dark-shadow-lg);
            --shadow-xl: var(--dark-shadow-xl);
            
            --bg-primary: var(--dark-bg-primary);
            --bg-secondary: var(--dark-bg-secondary);
            --bg-card: var(--dark-bg-card);
            --text-primary: var(--dark-text-primary);
            --text-secondary: var(--dark-text-secondary);
            --text-muted: var(--dark-text-muted);
            --border-color: var(--dark-border-color);
        }

        [data-theme="light"] {
            --bg-primary: var(--light-bg-primary);
            --bg-secondary: var(--light-bg-secondary);
            --bg-card: var(--light-bg-card);
            --text-primary: var(--light-text-primary);
            --text-secondary: var(--light-text-secondary);
            --text-muted: var(--light-text-muted);
            --border-color: var(--light-border-color);
            --shadow-sm: var(--light-shadow-sm);
            --shadow-md: var(--light-shadow-md);
            --shadow-lg: var(--light-shadow-lg);
            --shadow-xl: var(--light-shadow-xl);
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Inter', sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
            line-height: 1.6;
            overflow-x: hidden;
            transition: background-color 0.3s ease, color 0.3s ease;
        }
        
        body::before {
            content: '';
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: 
                radial-gradient(circle at 20% 30%, rgba(99, 102, 241, 0.1) 0%, transparent 50%),
                radial-gradient(circle at 80% 70%, rgba(139, 92, 246, 0.1) 0%, transparent 50%),
                radial-gradient(circle at 40% 80%, rgba(6, 182, 212, 0.1) 0%, transparent 50%);
            pointer-events: none;
            z-index: -1;
        }

        [data-theme="light"] body::before {
             background: 
                radial-gradient(circle at 20% 30%, rgba(99, 102, 241, 0.05) 0%, transparent 50%),
                radial-gradient(circle at 80% 70%, rgba(139, 92, 246, 0.05) 0%, transparent 50%),
                radial-gradient(circle at 40% 80%, rgba(6, 182, 212, 0.05) 0%, transparent 50%);
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 2rem;
        }
        
        .header {
            text-align: center;
            margin-bottom: 3rem;
            position: relative;
        }
        
        .header h1 {
            font-size: 3rem;
            font-weight: 700;
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
            margin-bottom: 1rem;
            text-shadow: 0 0 30px rgba(99, 102, 241, 0.3);
        }
        
        .header::after {
            content: '';
            position: absolute;
            bottom: -1rem;
            left: 50%;
            transform: translateX(-50%);
            width: 100px;
            height: 3px;
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            border-radius: 2px;
        }
        
        .status-badge {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.75rem 1.5rem;
            border-radius: 50px;
            font-weight: 600;
            font-size: 0.875rem;
            margin-top: 1rem;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            transition: all 0.3s ease;
        }
        
        .status-badge::before {
            content: '';
            width: 8px;
            height: 8px;
            border-radius: 50%;
            animation: pulse 2s infinite;
        }
        
        .status-connected {
            background: rgba(16, 185, 129, 0.2);
            color: var(--success-color);
        }
        
        .status-connected::before {
            background: var(--success-color);
        }
        
        .status-disconnected {
            background: rgba(239, 68, 68, 0.2);
            color: var(--error-color);
        }
        
        .status-disconnected::before {
            background: var(--error-color);
        }
        
        .status-loading {
            background: rgba(245, 158, 11, 0.2);
            color: var(--warning-color);
        }
        
        .status-loading::before {
            background: var(--warning-color);
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 2rem;
            margin-bottom: 3rem;
        }
        
        .card {
            background: var(--bg-card);
            backdrop-filter: blur(10px);
            border: 1px solid var(--border-color);
            border-radius: 20px;
            padding: 2rem;
            position: relative;
            overflow: hidden;
            transition: all 0.3s ease;
        }
        
        .card::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            height: 3px;
            background: linear-gradient(90deg, var(--primary-color), var(--secondary-color));
        }
        
        .card:hover {
            transform: translateY(-5px);
            box-shadow: var(--shadow-xl);
            border-color: rgba(99, 102, 241, 0.3);
        }
        
        .card h3 {
            color: var(--text-primary);
            margin-bottom: 1.5rem;
            font-size: 1.25rem;
            font-weight: 600;
            display: flex;
            align-items: center;
            gap: 0.75rem;
        }
        
        .card h3::before {
            content: attr(data-icon);
            font-size: 1.5rem;
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        
        .info-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 1rem;
            padding: 0.75rem;
            background: rgba(15, 23, 42, 0.3); /* Placeholder, will adjust for theme */
            border-radius: 12px;
            border: 1px solid rgba(255, 255, 255, 0.05); /* Placeholder, will adjust for theme */
            transition: all 0.3s ease;
        }

        [data-theme="light"] .info-row {
            background: rgba(226, 232, 240, 0.5); /* Light theme background */
            border-color: rgba(201, 203, 208, 0.3); /* Light theme border */
        }

        .info-row:hover {
            background: rgba(15, 23, 42, 0.5); /* Placeholder, will adjust for theme */
            border-color: rgba(99, 102, 241, 0.2);
        }

        [data-theme="light"] .info-row:hover {
            background: rgba(226, 232, 240, 0.7); /* Light theme hover background */
            border-color: rgba(99, 102, 241, 0.2);
        }
        
        .info-row:last-child {
            margin-bottom: 0;
        }
        
        .info-label {
            font-weight: 500;
            color: var(--text-secondary);
            font-size: 0.875rem;
        }
        
        .info-value {
            color: var(--text-primary);
            font-family: 'JetBrains Mono', monospace;
            font-weight: 500;
            text-align: right;
        }
        
        .signal-bars {
            display: flex;
            align-items: end;
            gap: 4px;
            height: 30px;
        }
        
        .signal-bar {
            width: 10px;
            background: rgba(148, 163, 184, 0.3);
            border-radius: 3px;
            transition: all 0.3s ease;
        }
        
        .signal-bar:nth-child(1) { height: 6px; }
        .signal-bar:nth-child(2) { height: 12px; }
        .signal-bar:nth-child(3) { height: 18px; }
        .signal-bar:nth-child(4) { height: 24px; }
        .signal-bar:nth-child(5) { height: 30px; }
        
        .signal-bar.active {
            background: linear-gradient(135deg, var(--success-color), var(--accent-color));
            box-shadow: 0 0 10px rgba(16, 185, 129, 0.5);
        }
        
        .signal-strength {
            margin-left: 1rem;
            font-weight: 600;
            color: var(--success-color);
        }
        
        .refresh-btn {
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            color: white;
            border: none;
            padding: 1rem 2rem;
            border-radius: 50px;
            cursor: pointer;
            font-size: 1rem;
            font-weight: 600;
            transition: all 0.3s ease;
            box-shadow: var(--shadow-md);
            position: relative;
            overflow: hidden;
        }
        
        .refresh-btn::before {
            content: '';
            position: absolute;
            top: 0;
            left: -100%;
            width: 100%;
            height: 100%;
            background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.2), transparent);
            transition: left 0.5s ease;
        }
        
        .refresh-btn:hover::before {
            left: 100%;
        }
        
        .refresh-btn:hover {
            transform: translateY(-2px);
            box-shadow: var(--shadow-lg);
        }
        
        .refresh-btn:active {
            transform: translateY(0);
        }
        
        .band-info {
            background: rgba(15, 23, 42, 0.5); /* Placeholder, will adjust for theme */
            padding: 0.75rem;
            border-radius: 8px;
            margin: 0.25rem 0;
            font-family: 'JetBrains Mono', monospace;
            border: 1px solid rgba(99, 102, 241, 0.2);
            font-size: 0.875rem;
        }

        [data-theme="light"] .band-info {
            background: rgba(226, 232, 240, 0.5); /* Light theme background */
            border-color: rgba(99, 102, 241, 0.15); /* Light theme border */
        }
        
        .mode-5g {
            color: var(--error-color);
            font-weight: 600;
            text-shadow: 0 0 10px rgba(239, 68, 68, 0.5);
        }
        
        .mode-lte {
            color: var(--accent-color);
            font-weight: 600;
            text-shadow: 0 0 10px rgba(6, 182, 212, 0.5);
        }
        
        /* --- Phần TỰ ĐỘNG LÀM MỚI ĐÃ BỊ ẨN --- */
        .auto-refresh {
            display: none !important; /* Ẩn vĩnh viễn */
            /* Các thuộc tính định vị khác không còn cần thiết nữa */
        }
        /* ------------------------------------------ */

        /* --- Điều chỉnh vị trí của theme-toggle --- */
        .theme-toggle {
            position: fixed;
            top: 2rem;
            right: 2rem; /* Đặt chế độ tối ở góc phải nhất */
            background: var(--bg-card); /* Adjust for theme */
            backdrop-filter: blur(10px);
            padding: 0.75rem 0.8rem; /* Điều chỉnh padding */
            border-radius: 15px;
            border: 1px solid var(--border-color); /* Adjust for theme */
            box-shadow: var(--shadow-lg);
            z-index: 1000;
            cursor: pointer;
            display: flex; /* Sử dụng flexbox */
            align-items: center; /* Căn giữa theo chiều dọc */
            gap: 0.4rem; /* Giảm khoảng cách */
            transition: all 0.3s ease;
            white-space: nowrap; /* Quan trọng: Ngăn chữ bị xuống dòng */
        }

        [data-theme="light"] .theme-toggle {
            background: rgba(255, 255, 255, 0.8);
            border-color: var(--light-border-color);
        }

        .theme-toggle:hover {
            transform: translateY(-2px);
            box-shadow: var(--shadow-xl);
        }

        .theme-toggle .icon {
            font-size: 1.2rem;
            flex-shrink: 0; /* Ngăn icon bị co lại */
        }

        /* Nếu có một phần tử bao bọc cho icon và chữ, hãy đảm bảo nó cũng xử lý như flex */
        .theme-toggle > div {
            display: flex;
            align-items: center;
            white-space: nowrap;
        }
        
        /* --- Responsive Design --- */
        @media (max-width: 768px) {
            .container {
                padding: 1rem;
            }
            
            .header h1 {
                font-size: 2rem;
            }
            
            .grid {
                grid-template-columns: 1fr;
                gap: 1.5rem;
            }
            
            .card {
                padding: 1.5rem;
            }
            
            /* --- Điều chỉnh cho màn hình nhỏ --- */
            /* Các phần tử auto-refresh và theme-toggle sẽ ở chế độ static */
            .auto-refresh, .theme-toggle {
                position: static; /* Hủy bỏ position: fixed */
                margin-left: auto;  /* Căn giữa */
                margin-right: auto; /* Căn giữa */
                margin-bottom: 2rem; /* Thêm khoảng cách bên dưới */
                max-width: 300px; /* Giới hạn chiều rộng */
                padding-left: 1rem; /* Thêm đệm hai bên */
                padding-right: 1rem;
                flex-wrap: wrap; /* Cho phép các item xuống dòng */
                justify-content: center; /* Căn giữa nội dung bên trong flex container */
            }
            
            /* Điều chỉnh riêng cho theme-toggle trên màn hình nhỏ */
            .theme-toggle {
                 margin-top: 1rem; /* Khoảng cách bên trên */
            }

            /* Đảm bảo cả hai đều hoạt động tốt khi stack */
            .auto-refresh {
                margin-bottom: 1rem; /* Giảm khoảng cách dưới auto-refresh khi stack */
            }

            /* Có thể cần điều chỉnh lại z-index hoặc display nếu stack bị chồng */
            .auto-refresh, .theme-toggle {
                z-index: 1000; /* Đảm bảo chúng ở trên các phần tử khác */
                display: flex;
                justify-content: center; /* Căn giữa nội dung bên trong */
            }
        }
        
        /* Animations */
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }
        
        .card {
            animation: fadeIn 0.5s ease-out;
        }
        
        .card:nth-child(1) { animation-delay: 0.1s; }
        .card:nth-child(2) { animation-delay: 0.2s; }
        .card:nth-child(3) { animation-delay: 0.3s; }
        .card:nth-child(4) { animation-delay: 0.4s; }
        .card:nth-child(5) { animation-delay: 0.5s; }
        .card:nth-child(6) { animation-delay: 0.6s; }
        
        /* Scrollbar Styling */
        ::-webkit-scrollbar {
            width: 8px;
        }
        
        ::-webkit-scrollbar-track {
            background: var(--bg-secondary);
        }
        
        ::-webkit-scrollbar-thumb {
            background: var(--primary-color);
            border-radius: 4px;
        }
        
        ::-webkit-scrollbar-thumb:hover {
            background: var(--secondary-color);
        }
    </style>
</head>
<body data-theme="dark">
    <div class="auto-refresh">
        <label>
            <input type="checkbox" id="autoRefresh" checked>
            Tự động làm mới (60s)
        </label>
        <div class="retry-count" id="retryCount">Lần thử: 0</div>
        <div class="countdown-timer" id="countdownTimer">Làm mới sau: 60s</div>
    </div>

    <div class="theme-toggle" id="themeToggle">
        <span class="icon">🌙</span>
        <span>Chế độ tối</span>
    </div>
    
    <div class="container">
        <div class="header">
            <h1>Sierra Wireless EM9190</h1>
            <div id="statusBadge" class="status-badge status-loading">Đang tải...</div>
        </div>
        
        <div id="errorMessage" class="error-message" style="display: none;"></div>
        
        <div class="grid">
            <div class="card">
                <h3 data-icon="📡">Thông tin kết nối</h3>
                <div class="info-row">
                    <span class="info-label">Nhà mạng:</span>
                    <span class="info-value" id="operator">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">MCC-MNC:</span>
                    <span class="info-value" id="mccmnc">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Vị trí:</span>
                    <span class="info-value" id="location">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Chế độ:</span>
                    <span class="info-value" id="mode">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Trạng thái:</span>
                    <span class="info-value" id="registration">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Thời gian kết nối:</span>
                    <span class="info-value" id="connTime">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">IP WAN:</span>
                    <span class="info-value" id="ipWan">Đang cập nhập</span>
                </div>
            </div>
            
            <div class="card">
                <h3 data-icon="📱">Thông tin thiết bị</h3>
                <div class="info-row">
                    <span class="info-label">Model:</span>
                    <span class="info-value" id="model">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Firmware:</span>
                    <span class="info-value" id="firmware">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Nhiệt độ:</span>
                    <span class="info-value" id="temp">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">IMEI:</span>
                    <span class="info-value" id="imei">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Port:</span>
                    <span class="info-value" id="port">-</span>
                </div>
            </div>
            
            <div class="card">
                <h3 data-icon="📶">Cường độ tín hiệu</h3>
                <div class="info-row">
                    <span class="info-label">Tín hiệu:</span>
                    <span class="info-value">
                        <div style="display: flex; align-items: center;">
                            <div class="signal-bars" id="signalBars">
                                <div class="signal-bar"></div>
                                <div class="signal-bar"></div>
                                <div class="signal-bar"></div>
                                <div class="signal-bar"></div>
                                <div class="signal-bar"></div>
                            </div>
                            <span class="signal-strength" id="signalPercent">-</span>
                        </div>
                    </span>
                </div>
                <div class="info-row">
                    <span class="info-label">CSQ:</span>
                    <span class="info-value" id="csq">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">RSRP:</span>
                    <span class="info-value" id="rsrp">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">RSRQ:</span>
                    <span class="info-value" id="rsrq">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">RSSI:</span>
                    <span class="info-value" id="rssi">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">SINR:</span>
                    <span class="info-value" id="sinr">-</span>
                </div>
            </div>
            
            <div class="card">
                <h3 data-icon="📡">Band tần</h3>
                <div class="info-row">
                    <span class="info-label">Band chính:</span>
                    <div class="band-info" id="pband">-</div>
                </div>
                <div class="info-row" id="s1bandRow" style="display: none;">
                    <span class="info-label">Band phụ 1:</span>
                    <div class="band-info" id="s1band">-</div>
                </div>
                <div class="info-row">
                    <span class="info-label">EARFCN:</span>
                    <span class="info-value" id="earfcn">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">PCI:</span>
                    <span class="info-value" id="pci">-</span>
                </div>
            </div>
            
            <div class="card">
                <h3 data-icon="📊">Dữ liệu</h3>
                <div class="info-row">
                    <span class="info-label">Dữ liệu nhận:</span>
                    <span class="info-value" id="rxData">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Dữ liệu gửi:</span>
                    <span class="info-value" id="txData">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">LAC:</span>
                    <span class="info-value" id="lac">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">CID:</span>
                    <span class="info-value" id="cid">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">TAC:</span>
                    <span class="info-value" id="tac">-</span>
                </div>
            </div>
            
            <div class="card">
                <h3 data-icon="💳">Thông tin SIM</h3>
                <div class="info-row">
                    <span class="info-label">IMSI:</span>
                    <span class="info-value" id="imsi">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">ICCID:</span>
                    <span class="info-value" id="iccid">-</span>
                </div>
                <div class="info-row">
                    <span class="info-label">Protocol:</span>
                    <span class="info-value" id="protocol">-</span>
                </div>
            </div>
        </div>
        
        <div class="button-container">
            <button class="refresh-btn" onclick="loadData()">🔄 Làm mới</button>
        </div>
    </div>
    
    <script>
        let autoRefreshInterval;
        let countdownInterval;
        let retryCount = 0;
        let maxRetries = 5;
        let countdown = 60;
        
        const themeToggle = document.getElementById('themeToggle');
        const body = document.body;

        // Function to set the theme
        function setTheme(theme) {
            document.documentElement.setAttribute('data-theme', theme);
            localStorage.setItem('theme', theme);
            const icon = theme === 'dark' ? '☀️' : '🌙';
            const text = theme === 'dark' ? 'Chế độ sáng' : 'Chế độ tối';
            themeToggle.querySelector('.icon').textContent = icon;
            themeToggle.querySelector('span:last-child').textContent = text;
        }

        // Function to toggle between themes
        function toggleTheme() {
            const currentTheme = document.documentElement.getAttribute('data-theme');
            const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
            setTheme(newTheme);
        }

        // Event listener for theme toggle
        themeToggle.addEventListener('click', toggleTheme);

        // Initialize theme from local storage or default to dark
        const savedTheme = localStorage.getItem('theme');
        if (savedTheme) {
            setTheme(savedTheme);
        } else {
            setTheme('dark'); // Default to dark mode
        }

        function formatBytes(bytes) {
            if (bytes === '-' || bytes === '' || bytes === null) return '-';
            const sizes = ['B', 'KB', 'MB', 'GB'];
            if (bytes === 0) return '0 B';
            const i = parseInt(Math.floor(Math.log(bytes) / Math.log(1024)));
            return Math.round(bytes / Math.pow(1024, i) * 100) / 100 + ' ' + sizes[i];
        }
        
        function updateSignalBars(percent) {
            const bars = document.querySelectorAll('.signal-bar');
            const activeCount = Math.ceil(percent / 20);
            
            bars.forEach((bar, index) => {
                if (index < activeCount) {
                    bar.classList.add('active');
                } else {
                    bar.classList.remove('active');
                }
            });
        }
        
        function showError(message) {
            const errorDiv = document.getElementById('errorMessage');
            errorDiv.textContent = message;
            errorDiv.style.display = 'block';
            setTimeout(() => {
                errorDiv.style.display = 'none';
            }, 5000);
        }
        
        function updateCountdown() {
            const countdownElement = document.getElementById('countdownTimer');
            if (countdown > 0) {
                countdownElement.textContent = `Làm mới sau: ${countdown}s`;
                countdown--;
            } else {
                countdownElement.textContent = 'Đang làm mới...';
                countdown = 60;
            }
        }
        
        function startCountdown() {
            countdown = 60;
            updateCountdown();
            countdownInterval = setInterval(updateCountdown, 1000);
        }
        
        function stopCountdown() {
            if (countdownInterval) {
                clearInterval(countdownInterval);
                countdownInterval = null;
            }
            document.getElementById('countdownTimer').textContent = 'Tắt tự động làm mới';
        }
        
        function loadData() {
            document.getElementById('statusBadge').textContent = 'Đang tải...';
            document.getElementById('statusBadge').className = 'status-badge status-loading';
            
            // Reset countdown when manually refreshing
            if (document.getElementById('autoRefresh').checked) {
                countdown = 60;
                document.getElementById('countdownTimer').textContent = 'Làm mới sau: 60s';
            }
            
            fetch('/cgi-bin/em9190-info')
                .then(response => {
                    if (!response.ok) {
                        throw new Error('HTTP ' + response.status);
                    }
                    return response.json();
                })
                .then(data => {
                    retryCount = 0;
                    document.getElementById('retryCount').textContent = 'Lần thử: 0';
                    
                    if (data.error) {
                        showError('Lỗi: ' + data.error);
                        return;
                    }
                    
                    // Update status
                    const statusBadge = document.getElementById('statusBadge');

                    if (data.ip_wan && data.ip_wan !== '-' && data.status === 'connected') {
                        statusBadge.textContent = 'Đã kết nối';
                        statusBadge.className = 'status-badge status-connected';
                    } else if (data.registration === '5') {
                        statusBadge.textContent = 'Roaming';
                        statusBadge.className = 'status-badge status-connected';
                    } else {
                        statusBadge.textContent = 'Mất kết nối';
                        statusBadge.className = 'status-badge status-disconnected';
                    }
                    
                    // Update all fields
                    document.getElementById('operator').textContent = data.operator_name || '-';
                    document.getElementById('mccmnc').textContent = data.operator_mcc && data.operator_mnc ? data.operator_mcc + '-' + data.operator_mnc : '-';
                    document.getElementById('location').textContent = data.location || '-';
                    
                    const modeElement = document.getElementById('mode');
                    const mode = data.mode || '-';
                    modeElement.innerHTML = mode.includes('5G') ? 
                        '<span class="mode-5g">' + mode + '</span>' : 
                        '<span class="mode-lte">' + mode + '</span>';
                    
                    const regText = data.registration === '1' ? 'Đã đăng ký' : 
                                   data.registration === '5' ? 'Roaming' : 
                                   data.registration === '0' ? 'Không đăng ký' : 
                                   data.registration === '2' ? 'Đang tìm' : 'Không xác định';
                    document.getElementById('registration').textContent = regText;
                    
                    document.getElementById('connTime').textContent = data.conn_time || '-';
                    document.getElementById('ipWan').textContent = data.ip_wan || '-';
                    document.getElementById('model').textContent = data.modem || '-';
                    document.getElementById('firmware').textContent = data.firmware || '-';
                    document.getElementById('temp').textContent = data.mtemp || '-';
                    document.getElementById('imei').textContent = data.imei || '-';
                    document.getElementById('port').textContent = data.cport || '-';
                    
                    // Signal
                    const signalPercent = data.signal || 0;
                    document.getElementById('signalPercent').textContent = signalPercent + '%';
                    updateSignalBars(signalPercent);
                    
                    document.getElementById('csq').textContent = data.csq || '-';
                    document.getElementById('rsrp').textContent = data.rsrp ? data.rsrp + ' dBm' : '-';
                    document.getElementById('rsrq').textContent = data.rsrq ? data.rsrq + ' dB' : '-';
                    document.getElementById('rssi').textContent = data.rssi ? data.rssi + ' dBm' : '-';
                    document.getElementById('sinr').textContent = data.sinr ? data.sinr + ' dB' : '-';
                    
                    // Bands
                    document.getElementById('pband').textContent = data.pband || '-';
                    document.getElementById('earfcn').textContent = data.earfcn || '-';
                    document.getElementById('pci').textContent = data.pci || '-';
                    
                    const s1bandRow = document.getElementById('s1bandRow');
                    if (data.s1band && data.s1band !== '-') {
                        s1bandRow.style.display = 'flex';
                        document.getElementById('s1band').textContent = data.s1band;
                    } else {
                        s1bandRow.style.display = 'none';
                    }
                    
                    // Data
                    document.getElementById('rxData').textContent = formatBytes(data.rx);
                    document.getElementById('txData').textContent = formatBytes(data.tx);
                    document.getElementById('lac').textContent = data.lac_dec && data.lac_hex ? data.lac_dec + ' (0x' + data.lac_hex + ')' : '-';
                    document.getElementById('cid').textContent = data.cid_dec && data.cid_hex ? data.cid_dec + ' (0x' + data.cid_hex + ')' : '-';
                    document.getElementById('tac').textContent = data.tac_d && data.tac_h ? data.tac_d + ' (0x' + data.tac_h + ')' : '-';
                    
                    // SIM
                    document.getElementById('imsi').textContent = data.imsi || '-';
                    document.getElementById('iccid').textContent = data.iccid || '-';
                    document.getElementById('protocol').textContent = data.protocol || '-';
                })
                .catch(error => {
                    console.error('Error:', error);
                    retryCount++;
                    document.getElementById('retryCount').textContent = 'Lần thử: ' + retryCount;
                    
                    if (retryCount >= maxRetries) {
                        document.getElementById('statusBadge').textContent = 'Lỗi kết nối';
                        document.getElementById('statusBadge').className = 'status-badge status-disconnected';
                        showError('Không thể kết nối sau ' + maxRetries + ' lần thử');
                        stopCountdown(); // Stop countdown if max retries reached
                    } else {
                        document.getElementById('statusBadge').textContent = 'Đang thử lại...';
                        document.getElementById('statusBadge').className = 'status-badge status-loading';
                        setTimeout(loadData, 2000);
                    }
                });
        }
        
        function toggleAutoRefresh() {
            const checkbox = document.getElementById('autoRefresh');
            if (checkbox.checked) {
                autoRefreshInterval = setInterval(loadData, 60000); // 60 seconds
                startCountdown();
            } else {
                clearInterval(autoRefreshInterval);
                stopCountdown();
            }
        }
        
        document.getElementById('autoRefresh').addEventListener('change', toggleAutoRefresh);
        
        // Manual refresh button resets countdown
        document.querySelector('.refresh-btn').addEventListener('click', function() {
            if (document.getElementById('autoRefresh').checked) {
                clearInterval(countdownInterval);
                startCountdown();
            }
        });
        
        // Initial load
        loadData();
        toggleAutoRefresh();
    </script>
</body>
</html>
EOF

# 3. Tạo CGI script
echo "Tạo CGI script..."
cat > "$CGI_DIR/em9190-info" << 'EOF'
#!/bin/sh

echo "Content-Type: application/json"
echo ""

DEVICE="/dev/ttyUSB0"

# ==== HÀM PHỤ ====

get_at_response() {
    CMD="$1"
    FILTER="$2"
    sms_tool -d "$DEVICE" at "$CMD" > /tmp/at_resp.txt 2>/dev/null
    grep "$FILTER" /tmp/at_resp.txt | tail -1
}

get_single_line_value() {
    CMD="$1"
    sms_tool -d "$DEVICE" at "$CMD" 2>/dev/null | grep -vE '^(AT|\s*OK|\s*$)' | head -1 | tr -d '\r\n '
}

get_imsi() {
    get_single_line_value "AT+CIMI"
}

get_iccid() {
    sms_tool -d "$DEVICE" at "AT+ICCID" 2>/dev/null | grep -i "ICCID" | awk -F: '{print $2}' | tr -d '\r\n "'
}

sanitize_string() {
    [ -z "$1" ] && echo "-" || echo "$1" | tr -d '\r\n'
}

sanitize_number() {
    [ -z "$1" ] && echo "-" || echo "$1"
}

get_connection_status() {
    IFACE=$(ip route | awk '/default/ {print $5}' | head -1)
    WAN_IP=$(ip addr show "$IFACE" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
    if [ -z "$WAN_IP" ] || echo "$WAN_IP" | grep -qE '^(0\.0\.0\.0|169\.)'; then
        echo "disconnected"
    else
        echo "connected"
    fi
}

# ==== GSTATUS CHÍNH ====
O=$(sms_tool -d "$DEVICE" at "AT!GSTATUS?" 2>/dev/null)

# ==== THÔNG TIN MODEM ====
MODEL=$(sms_tool -d "$DEVICE" at "AT+CGMM" 2>/dev/null | grep -v -e '^AT' -e '^OK' -e '^$' | head -n1 | tr -d '\r\n')
FW=$(sms_tool -d "$DEVICE" at "AT+CGMR" 2>/dev/null | grep -v -e '^AT' -e '^OK' -e '^$' | head -n1 | tr -d '\r\n')
IMEI=$(sanitize_string "$(get_single_line_value 'AT+CGSN')")
IMSI=$(sanitize_string "$(get_imsi)")
ICCID=$(sanitize_string "$(get_iccid)")


# ==== NHIỆT ĐỘ, MODE ====
TEMP=$(echo "$O" | awk -F: '/Temperature:/ {print $3}' | xargs)
SYS_MODE=$(echo "$O" | awk '/^System mode:/ {print $3}')
case "$SYS_MODE" in
    "LTE") MODE="LTE" ;;
    "ENDC") MODE="5G NSA" ;;
    *) MODE="-" ;;
esac

# ==== TAC ====
TAC_HEX=$(echo "$O" | awk '/.*TAC:/ {print $6}')
[ -n "$TAC_HEX" ] && TAC_DEC=$(printf "%d" "0x$TAC_HEX")

# ==== CID, LAC, PCI ====
CID_HEX=$(echo "$O" | awk '/.*TAC:/ {gsub(/[()]/, "", $7); print $7}' )
[ -n "$CID_HEX" ] && CID_DEC=$(printf "%d" "0x$CID_HEX")
PCI=$(echo "$O" | awk '/.*TAC:/ {print $8}' | sed 's/[,)]//g')

# ==== TÍN HIỆU ====
RSRP=$(echo "$O" | awk '/^PCC/ && /RSRP/ {print $8}' | head -1 | xargs)
RSSI=$(echo "$O" | awk '/^PCC/ && /RSSI/ {print $4}' | head -1 | xargs)
RSRQ=$(echo "$O" | grep "^RSRQ" | awk '{print $3}')
SINR=$(echo "$O" | grep "^SINR" | awk '{print $3}')
[ -z "$RSRQ" ] && RSRQ="-"
[ -z "$SINR" ] && SINR="-"


# ==== BĂNG TẦN CHÍNH ====
BAND=$(echo "$O" | awk '/^LTE band:/ {print $3}')
FREQ=$(echo "$O" | awk '/^LTE band:/ {print $6}')
PBAND="B${BAND/B/} @${FREQ} MHz"
MODE="$MODE B${BAND/B/}"

# ==== SCC BANDS ====
get_band_string() {
    echo -n "B$1"
    case "$1" in
        "1") echo -n " (2100 MHz)";;
        "3") echo -n " (1800 MHz)";;
        "7") echo -n " (2600 MHz)";;
        "8") echo -n " (900 MHz)";;
        "20") echo -n " (800 MHz)";;
        "28") echo -n " (700 MHz)";;
        "40") echo -n " (2300 MHz)";;
        *) echo -n "";;
    esac
}

get_scc_band() {
    SCC_NO="$1"
    ACTIVE=$(echo "$O" | awk -F: "/^LTE SCC${SCC_NO} state:.*ACTIVE/ {print \$3}")
    if [ -n "$ACTIVE" ]; then
        BW=$(echo "$O" | awk "/^LTE SCC${SCC_NO} bw/ {print \$5}")
        BSTR="B${ACTIVE/B/}"
        MODE="${MODE/LTE/LTE-A} + $BSTR"
        echo "$(get_band_string ${ACTIVE/B/}) @$BW MHz"
    else
        echo "-"
    fi
}

S1BAND=$(get_scc_band 1)
S2BAND=$(get_scc_band 2)
S3BAND=$(get_scc_band 3)

# ==== 5G NR ====
NRBAND=$(echo "$O" | awk '/^SCC. NR5G band:/ {print $4}')
if [ -n "$NRBAND" ] && [ "$NRBAND" != "---" ]; then
    MODE="$MODE + n${NRBAND/n/}"
    NR_RSRP=$(echo "$O" | awk '/SCC. NR5G RSRP:/ {print $4}')
    NR_RSRQ=$(echo "$O" | awk '/SCC. NR5G RSRQ:/ {print $4}')
    NR_SINR=$(echo "$O" | awk '/SCC. NR5G SINR:/ {print $4}')
    [ -n "$NR_RSRP" ] && RSRP="$NR_RSRP"
    [ -n "$NR_RSRQ" ] && RSRQ="$NR_RSRQ"
    [ -n "$NR_SINR" ] && SINR="$NR_SINR"
fi

# ==== CSQ ====
CSQ_LINE=$(get_at_response "AT+CSQ" "+CSQ")
CSQ=$(echo "$CSQ_LINE" | awk -F: '{print $2}' | awk -F, '{print $1}' | tr -d ' ')
if [ -n "$CSQ" ] && [ "$CSQ" -ne 99 ]; then
    CSQ_PER=$(expr $CSQ \* 100 / 31)
else
    CSQ="0"
    CSQ_PER="0"
fi

# ==== COPS (lấy MCC/MNC đúng) ====
sms_tool -d "$DEVICE" at "AT+COPS=3,2" > /dev/null 2>&1
COPS_LINE=$(get_at_response "AT+COPS?" "+COPS")
COPS_NUM=$(echo "$COPS_LINE" | grep -oE '[0-9]{5,6}' | head -1)

case "$COPS_NUM" in
    "45202") COPS="Vinaphone";;
    "45201") COPS="Mobifone";;
    "45204") COPS="Viettel";;
    *)       COPS="Unknown";;
esac

COPS_MCC=$(echo "$COPS_NUM" | cut -c1-3)
COPS_MNC=$(echo "$COPS_NUM" | cut -c4-)

# ==== CREG ====
CREG_LINE=$(get_at_response "AT+CREG?" "+CREG")
REG_STATUS=$(echo "$CREG_LINE" | awk -F, '{print $2}' | tr -d ' ')

# ==== EARFCN ====
EARFCN=$(echo "$O" | awk '/^LTE Rx chan:/ {print $4}')

# ==== PROTOCOL ====
PROTO_INFO=$(awk '/Vendor=1199 ProdID=90d3/{f=1} f && /Driver=/{print; f=0}' /sys/kernel/debug/usb/devices 2>/dev/null)
case "$PROTO_INFO" in
    *qmi_wwan*) PROTO="qmi";;
    *cdc_mbim*) PROTO="mbim";;
    *cdc_ether*) PROTO="ecm";;
    *) PROTO="qmi";;
esac

# ==== RX/TX, IP, STATUS ====
# --- Rx/Tx + IP ---
IFACE=$(ip route | awk '/default/ {print $5}' | head -1)
RX_BYTES=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null || echo "0")
TX_BYTES=$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null || echo "0")
UPTIME=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)
CONN_TIME=$(printf "%02d:%02d:%02d" $((UPTIME/3600)) $((UPTIME%3600/60)) $((UPTIME%60)))

# --- Kiểm tra trạng thái kết nối WAN ---
IP_WAN=$(ip addr show "$IFACE" 2>/dev/null | awk '/inet / {print $2}' | cut -d'/' -f1 | grep -v '^127' | head -n1)
if [ -n "$IP_WAN" ]; then
    STATUS="connected"
else
    STATUS="disconnected"
    IP_WAN="-"
fi


# ==== IN JSON ====
cat << JSONEOF
{
    "conn_time": "$(sanitize_string "$CONN_TIME")",
    "rx": "$(sanitize_number "$RX_BYTES")",
    "tx": "$(sanitize_number "$TX_BYTES")",
    "status": "$(sanitize_string "$STATUS")",
    "ip_wan": "$(sanitize_string "$IP_WAN")",
    "modem": "Sierra Wireless AirPrime EM9190 5G NR",
    "mtemp": "$(sanitize_string "$TEMP")",
    "firmware": "SWIX55C_03.10.07.00",
    "cport": "$(sanitize_string "$DEVICE")",
    "protocol": "$(sanitize_string "$PROTO")",
    "csq": "$(sanitize_number "$CSQ")",
    "signal": "$(sanitize_number "$CSQ_PER")",
    "operator_name": "$(sanitize_string "$COPS")",
    "operator_mcc": "$(sanitize_string "$COPS_MCC")",
    "operator_mnc": "$(sanitize_string "$COPS_MNC")",
    "location": "Việt Nam",
    "mode": "$(sanitize_string "$MODE")",
    "registration": "$(sanitize_string "$REG_STATUS")",
    "imei": "$(sanitize_string "$IMEI")",
    "imsi": "$(sanitize_string "$IMSI")",
    "iccid": "$(sanitize_string "$ICCID")",
    "lac_dec": "$(sanitize_number "$TAC_DEC")",
    "lac_hex": "$(sanitize_string "$TAC_HEX")",
    "cid_dec": "$(sanitize_number "$CID_DEC")",
    "cid_hex": "$(sanitize_string "$CID_HEX")",
    "pci": "$(sanitize_number "$PCI")",
    "earfcn": "$(sanitize_number "$EARFCN")",
    "pband": "$(sanitize_string "$PBAND")",
    "s1band": "$(sanitize_string "$S1BAND")",
    "s2band": "$(sanitize_string "$S2BAND")",
    "s3band": "$(sanitize_string "$S3BAND")",
    "rsrp": "$(sanitize_number "$RSRP")",
    "rsrq": "$(sanitize_number "$RSRQ")",
    "rssi": "$(sanitize_number "$RSSI")",
    "sinr": "$(sanitize_number "$SINR")"
}
JSONEOF

EOF

# 4. Cấp quyền thực thi cho CGI
echo "Cấp quyền thực thi cho CGI..."
chmod +x "$CGI_DIR/em9190-info"

# 5. Cấu hình uhttpd
echo "Cấu hình uhttpd..."

# Backup config gốc
cp "$UHTTPD_CONFIG" "$UHTTPD_CONFIG.backup"

# Thêm config mới
cat >> "$UHTTPD_CONFIG" << EOF

config uhttpd 'em9190'
	option home '/www/em9190'
	option cgi_prefix '/cgi-bin'
	list listen_http '0.0.0.0:$PORT'
	list listen_http '[::]:$PORT'
	option redirect_https '0'
	option rfc1918_filter '0'
	option max_requests '10'
	option max_connections '100'
	option tcp_keepalive '1'
	option ubus_prefix '/ubus'
	option index_file 'index.html'
	option error_page '/error.html'
	option script_timeout '60'
	option network_timeout '30'
	option http_keepalive '20'
	option tcp_keepalive '1'
EOF

# 6. Khởi động dịch vụ
echo "Khởi động dịch vụ uhttpd..."
/etc/init.d/uhttpd restart

# 7. Kiểm tra và hiển thị kết quả
echo ""
echo "=== Cài đặt hoàn tất ==="
echo ""
echo "Thông tin truy cập:"
echo "- URL: http://$(ip route get 1 | awk '{print $NF;exit}'):$PORT"
echo "- Port: $PORT"
echo "- Thư mục web: $WEB_DIR"
echo ""
echo "Kiểm tra dịch vụ:"
if netstat -ln 2>/dev/null | grep -q ":$PORT " || ss -ln 2>/dev/null | grep -q ":$PORT "; then
    echo "✅ Dịch vụ uhttpd đang chạy trên port $PORT"
else
    echo "❌ Dịch vụ uhttpd chưa khởi động"
fi

echo ""
echo "Để gỡ cài đặt, chạy:"
echo "rm -rf $WEB_DIR"
echo "sed -i '/em9190/,/^$/d' $UHTTPD_CONFIG"
echo "/etc/init.d/uhttpd restart"
echo ""
echo "Truy cập: http://$(ip route get 1 | awk '{print $NF;exit}'):$PORT"
