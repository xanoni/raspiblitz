#!/bin/bash

redisVersion="6.0.9"

sudo apt install -y tcl

cd /home/admin/download
rm -rf /home/admin/download/*
wget http://download.redis.io/releases/redis-${redisVersion}.tar.gz
tar xzf redis-${redisVersion}.tar.gz
cd redis-${redisVersion}/
make && sudo make install

sudo mkdir /mnt/hdd/redis
sudo adduser --system --group --no-create-home redis
sudo chown redis:redis /mnt/hdd/redis
sudo chmod 770 /mnt/hdd/redis
sudo mkdir /etc/redis
sudo sed -i "s/^supervised .*/supervised systemd/g" redis.conf
sudo sed -i "s/^dir .\//dir \/mnt\/hdd\/redis/g" redis.conf
sudo cp redis.conf /etc/redis

sudo tee /etc/systemd/system/redis.service >/dev/null <<EOF
[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
User=redis
Group=redis
ExecStart=/usr/local/bin/redis-server /etc/redis/redis.conf
ExecStop=/usr/local/bin/redis-cli shutdown
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start redis
sudo systemctl status redis --no-pager

sudo systemctl enable redis

bash /home/admin/config.scripts/bonus.nodejs.sh on

sudo ufw allow 3050 comment 'allow LndHub'
sudo ufw reload

cd /home/admin/download/
sudo git clone https://github.com/BlueWallet/LndHub
cd /home/admin
sudo mv /home/admin/download/LndHub /home/bitcoin/
sudo mv /home/bitcoin/LndHub /home/bitcoin/.lndhub
sudo cp /home/admin/.lnd/data/chain/bitcoin/mainnet/admin.macaroon /home/bitcoin/.lndhub/
sudo cp /home/admin/.lnd/tls.cert /home/bitcoin/.lndhub/
sudo chown -R bitcoin:bitcoin /home/bitcoin/.lndhub/

rpcuser=raspibolt
rpcpassword=passowrd_b

sudo -u bitcoin tee /home/bitcoin/.lndhub/config.js >/dev/null <<EOF
let config = {
  enableUpdateDescribeGraph: false,
  postRateLimit: 100,
  rateLimit: 200,
  bitcoind: {
    rpc: 'http://${rpcuser}:${rpcpassword}@$127.0.0.1:8332/wallet/wallet.dat',
  },
  redis: {
    port: 6379,
    host: '127.0.0.1',
    family: 4,
    db: 0,
  },
  lnd: {
    url: '127.0.0.1:10009',
    password: '',
  },
};

if (process.env.CONFIG) {
  console.log('using config from env');
  config = JSON.parse(process.env.CONFIG);
}

module.exports = config;
EOF

sudo npm config set prefix '/home/bitcoin/.npm-global'
export PATH=/home/bitcoin/.npm-global/bin:$PATH
sudo npm install

cd /home/bitcoin/.lndhub
npm install @babel/cli -g
npm install @babel/core -g
sudo -u bitcoin mkdir /home/bitcoin/.lndhub/build
sudo -u bitcoin sed -i "s/^let server = app.listen(process.env.PORT || 3000.*/let server = app.listen\(process.env.PORT || 3050, function () {/g" /home/bitcoin/.lndhub/index.js
sudo -u bitcoin sed -i "s/^  logger.log('BOOTING UP', 'Listening on port ' + (process.env.PORT || 3000));/  logger.log('BOOTING UP', 'Listening on port ' + (process.env.PORT || 3050));/g" /home/bitcoin/.lndhub/index.js
npm run babel ./ --out-dir ./build --copy-files --ignore node_modules
cd /home/admin

sudo node /home/bitcoin/.lndhub/build/index.js

sudo tee /etc/systemd/system/lndhub.service >/dev/null <<EOF
[Unit]
Description=LndHub Wrapper for Lightning Daemon
Wants=lnd.service
After=lnd.service

[Service]
WorkingDirectory=/home/bitcoin/.lndhub
ExecStart=/usr/bin/node build/index.js

User=bitcoin
Group=bitcoin
Type=simple
KillMode=process
LimitNOFILE=128000
TimeoutSec=240
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable lndhub
sudo systemctl start lndhub

echo
echo "DONE"
