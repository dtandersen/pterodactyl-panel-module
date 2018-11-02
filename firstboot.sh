#!/bin/bash
# who needs security}
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0

yum update -y -q

yum install -y yum-utils
yum install -y epel-release https://centos7.iuscommunity.org/ius-release.rpm
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

yum update -y -q

yum install -y -q nano nginx \
  firewalld \
  certbot \
  php72u-common php72u-fpm php72u-cli php72u-json php72u-mysqlnd php72u-gd php72u-mbstring php72u-pdo php72u-zip php72u-bcmath php72u-dom php72u-opcache \
  yum-utils device-mapper-persistent-data lvm2 \
  docker-ce \
  tar unzip make gcc gcc-c++ python \
  nodejs

systemctl enable docker
systemctl start docker

docker run --name mariadb \
  -d --restart unless-stopped \
  -e MYSQL_ROOT_PASSWORD=${mysql_root_password} \
  -e MYSQL_DATABASE=${mysql_database} \
  -e MYSQL_USER=${mysql_user} \
  -e MYSQL_PASSWORD=${mysql_password} \
  -v /var/lib/mysql:/var/lib/mysql \
  -p 3306:3306 \
  mariadb

docker run --name redis \
  -d --restart unless-stopped \
  -v /var/lib/redis:/data \
  -p 6379:6379 \
  redis \
  redis-server --appendonly yes

systemctl start firewalld
systemctl enable firewalld
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-service=http
firewall-cmd --add-service=https

curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

systemctl stop nginx

certbot certonly --non-interactive --agree-tos --email ${EMAIL} --standalone --preferred-challenges http -d ${DOMAIN}

#cp /vagrant/nginx.conf /etc/nginx/conf.d/pterodactyl.conf

cat <<'EOF' > /etc/nginx/conf.d/pterodactyl.conf
server_tokens off;

server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2;
    ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256';
    ssl_prefer_server_ciphers on;

    # See https://hstspreload.org/ before uncommenting the line below.
    # add_header Strict-Transport-Security "max-age=15768000; preload;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php-fpm/pterodactyl.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

systemctl enable nginx
systemctl start nginx

#cp /vagrant/www-pterodactyl.conf /etc/php-fpm.d/www-pterodactyl.conf
cat <<'EOF' > /etc/php-fpm.d/www-pterodactyl.conf
[pterodactyl]
user = nginx
group = nginx

listen = /var/run/php-fpm/pterodactyl.sock
listen.owner = nginx
listen.group = nginx
listen.mode = 0750

pm = ondemand
pm.max_children = 9
pm.process_idle_timeout = 10s
pm.max_requests = 200
EOF

systemctl enable php-fpm
systemctl start php-fpm

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

curl -Lso panel.tar.gz https://github.com/Pterodactyl/Panel/releases/download/v0.7.10/panel.tar.gz
tar --strip-components=1 -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache

cp .env.example .env
composer install -q --no-dev --optimize-autoloader

php artisan key:generate --force
php artisan p:environment:setup --author=${EMAIL} --url=https://${DOMAIN} --timezone=America/Los_Angeles --cache=redis --session=redis --queue=redis --disable-settings-ui --redis-host=localhost --redis-pass= --redis-port=6379
php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=${mysql_database} --username=${mysql_user} --password=${mysql_password}
php artisan p:environment:mail --driver=smtp --host=localhost --port=2525 -n --encryption=
php artisan migrate --no-interaction --force
php artisan db:seed -n --force
php artisan p:user:make --admin=1 --email=${EMAIL} --username=${admin_user}  --password=${admin_password} --name-first=${admin_first} --name-last=${admin_last}
chown -R nginx:nginx $(pwd)
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/pterodactyl/storage(/.*)?"
restorecon -R /var/www/pterodactyl
#cp /vagrant/pteroq.service /etc/systemd/system

cat <<'EOF' > /etc/systemd/system/pteroq.service
# Pterodactyl Queue Worker File
# ----------------------------------
# File should be placed in:
# /etc/systemd/system
#
# nano /etc/systemd/system/pteroq.service

[Unit]
Description=Pterodactyl Queue Worker

[Service]
User=nginx
Group=nginx
Restart=on-failure
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable pteroq.service
sudo systemctl start pteroq

#cp /vagrant/ptero /etc/cron.d
cat <<'EOF' > /etc/cron.d/ptero
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1
EOF
