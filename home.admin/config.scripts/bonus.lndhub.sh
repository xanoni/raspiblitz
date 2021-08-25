#! /usr/bin/env -S bash -ex

################################################################################
####################### WORK IN PROGRESS — DO NOT USE ##########################
################################################################################

REDIS_DIR="/mnt/hdd/redis"
REDIS_CONFIG="/etc/redis/redis.conf"
REDIS_SYSTEMD="/etc/systemd/system/redis.service"

LND_DIR="/home/admin/.lnd"

LNDHUB_DIR="/home/bitcoin/.lndhub" # TODO: do all of this on the HDD instead?
LNDHUB_USR="bitcoin"
LNDHUB_GRP="bitcoin"
LNDHUB_PORT=3050

## get redis from apt
sudo apt install -y redis-server

## create alternative redis directory on SSD
sudo mkdir --mode=750 "${REDIS_DIR}"
sudo chown redis:redis "${REDIS_DIR}"

## tweak redis.conf to reflect new dir
sudo sed -i \
    "s|^supervised .*|supervised systemd|" \
    "${REDIS_CONFIG}"

sudo sed -i \
    "s|^dir .*|dir ${REDIS_DIR}|" \
    "${REDIS_CONFIG}"

## TODO: tweak remaining redis settings

## add ${REDIS_DIR} to writable directories
sudo sed -i \
    "/^ReadOnlyDirectories=.*\$/a ReadWriteDirectories=-${REDIS_DIR}" \
    "${REDIS_SYSTEMD}"

sudo systemctl enable --now redis.service
sudo systemctl status redis.service --no-pager

## install node.js
/home/admin/config.scripts/bonus.nodejs.sh on

## get the LndHub code
sudo -u "${LNDHUB_USR}" git clone \
    "https://github.com/BlueWallet/LndHub" \
    "${LNDHUB_DIR}"

## copy cert and macaroon from lnd
sudo install \
    --owner="${LNDHUB_USR}" --group="${LNDHUB_GRP}" --mode=600 \
    --target-directory="${LNDHUB_DIR}" \
    "${LND_DIR}/data/chain/bitcoin/mainnet/admin.macaroon" \
    "${LND_DIR}/tls.cert"

# TODO: need to get actual credentials and URLencode them
rpcuser=raspibolt
rpcpassword=password_b

## create a config for LndHub
sudo -u "${LNDHUB_USR}" tee "${LNDHUB_DIR}/config.js" > /dev/null <<EOF
# config.js (for LndHub)

let config = {
  //enableUpdateDescribeGraph: false,
  //postRateLimit: 100,
  //rateLimit: 200,
  bitcoind: {
    rpc: 'http://${rpcuser}:${rpcpassword}@127.0.0.1:8332',
  },
  redis: {
    port: 6379,
    host: '127.0.0.1',
    family: 4,
    //password: 'NOT USED',
    db: 0,
  },
  lnd: {
    url: '127.0.0.1:10009',
    //password: '',
  },
};

if (process.env.CONFIG) {
  console.log('Using LndHub config from env ...');
  config = JSON.parse(process.env.CONFIG);
}

module.exports = config;
EOF

## prepare the LndHub user's node installation and update $PATH
sudo -iu "${LNDHUB_USR}" npm config set prefix "/home/${LNDHUB_USR}/.npm-global/"

echo "if [ -d \"\${HOME}/.npm-global/bin\" ]; then
    PATH=\"\${HOME}/.npm-global/bin:\${PATH}\"
fi" | sudo -iu "${LNDHUB_USR}" tee -a "/home/${LNDHUB_USR}/.bashrc"

## build LndHub and its dependencies
sudo -u "${LNDHUB_USR}" \
    bash -ic "(cd \'${LNDHUB_DIR}\' && npm i && npm i -g @babel/cli @babel/core && mkdir build)"
sudo -u "${LNDHUB_USR}" \
    bash -ic "(cd \'${LNDHUB_DIR}\' && babel ./ --out-dir ./build --copy-files --ignore node_modules)"

## create hardened systemd unit file for LndHub
sudo tee /etc/systemd/system/lndhub.service > /dev/null <<EOF
# systemd unit for LndHub
# /etc/systemd/system/lndhub.service

[Unit]

Description=LndHub Wrapper for Lightning Daemon
After=lnd.service bitcoind.service tor.service
Wants=lnd.service tor.service


[Service]

# Service execution
###################

Environment="PORT=${LNDHUB_PORT}"
WorkingDirectory=${LNDHUB_DIR}
ExecStart=/usr/bin/node build/index.js


# Process management
####################

Type=simple
KillMode=process
Restart=always
RestartSec=15
TimeoutSec=45


# Process priority
##################

LimitNOFILE=128000
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=2


# Directory creation and permissions
####################################

User=bitcoin
Group=bitcoin

# /run/bitcoind
RuntimeDirectory=lndhub
RuntimeDirectoryMode=0710


# Hardening measures
####################

# Provide a private /tmp and /var/tmp
PrivateTmp=true

# Mount /usr, /boot/ and /etc read-only for the process
ProtectSystem=full

# TODO: Deny access to /home, /root and /run/user
ProtectHome=false

# Disallow the process and all of its children to gain
# new privileges through execve()
NoNewPrivileges=true

# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random
PrivateDevices=true


[Install]
WantedBy=multi-user.target
EOF

## allow LndHub port in ufw and start service
sudo ufw allow "${LNDHUB_PORT}/tcp" comment "allow LndHub"
sudo systemctl enable --now lndhub.service

echo -en "\nDONE\n"
