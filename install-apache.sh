#!/bin/bash

domain="adownoe.store"
sub_domain="www.amazon.${domain}"
sub_domains=("$sub_domain" "amazon.${domain}" "${domain}" "www.${domain}")
cloudflare_api_token="UchG6N78CdmVOHsIimLcIEshnRCqRCJdi5p4Jg6b"
email="dadanew07559@proton.me"
html_allowed_paths="/signin/ap"

echo "打开防火墙相应入站端口..."
ufw enable
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 80/tcp
ufw reload
echo "防火墙入站端口 22 443 80 均已打开..."

echo "apache 安装..."
apt install -y apache2
echo "重启 apache ..."
systemctl restart apache2

echo "启用 URL 重写..."
a2enmod rewrite
systemctl restart apache2

echo "启用 ssl 模块..."
a2enmod ssl
systemctl restart apache2

echo "安装 certbot 以申请证书..."
apt install -y certbot
systemctl restart apache2

echo "安装 cloudflare 插件以自动化申请证书..."
apt install -y python3-certbot-dns-cloudflare
systemctl restart apache2

echo "安装 python3-certbot-apache 以配置证书..."
apt install -y python3-certbot-apache
systemctl restart apache2

echo "安装系统整体的 php 模块..."
apt install -y php
systemctl restart apache2

echo "安装 apache 的 php 模块..."
apt install -y libapache2-mod-php
systemctl restart apache2

echo "申请通配符证书..."
mkdir -p /etc/letsencrypt
echo "dns_cloudflare_api_token = $cloudflare_api_token" | tee /etc/letsencrypt/cloudflare.ini > /dev/null
chmod 600 /etc/letsencrypt/cloudflare.ini
certbot certonly --dns-cloudflare --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60 \
  -m "$email" --agree-tos --no-eff-email \
  $(for sub in "${sub_domains[@]}"; do echo -n "-d $sub "; done)
systemctl restart apache2

echo "配置 http 重定向到 https..."
bash -c "cat > /etc/apache2/sites-available/${domain}.conf << EOL
<VirtualHost *:80>
    ServerName ${domain}
    ServerAlias *.${domain}
    DocumentRoot /var/www/html
    ErrorLog /var/log/apache2/error.log
    CustomLog /var/log/apache2/access.log combined
    <Directory \"/var/www/html\">
        AllowOverride All
        Options FollowSymLinks
        RewriteEngine On
        RewriteRule ^(.*)$ https://${sub_domain}${html_allowed_paths} [R=301,L]
    </Directory>
</VirtualHost>
EOL"
systemctl restart apache2

echo "启用 domain http 站点..."
a2ensite "${domain}.conf"
systemctl restart apache2

echo "配置 SSL 虚拟主机..."
bash -c "cat > /etc/apache2/sites-available/adownoe.store-le-ssl.conf << EOL
<IfModule mod_ssl.c>
    <VirtualHost *:443>
        ServerName ${domain}
        ServerAlias ${sub_domains[*]}
        DocumentRoot /var/www/html
        ErrorLog /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log combined
        SSLEngine on
        SSLCertificateFile /etc/letsencrypt/live/${sub_domain}/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/${sub_domain}/privkey.pem
        Include /etc/letsencrypt/options-ssl-apache.conf
    </VirtualHost>
</IfModule>
EOL"
systemctl restart apache2
a2enmod ssl
systemctl restart apache2

echo "去掉自编辑代码文件中的注释部分..."
find /tmp/data/index/ -type f ! -name "*.png" -exec sed -i '/^\s*\/\//d; /^\s*#/d' {} +

echo "移动 index 文件包到默认位置..."
mv /tmp/data/index/* /var/www/html/
chmod -R 644 /var/www/html/*
chown -R www-data:www-data /var/www/html/
chmod -R 755 /var/www/html
chown -R www-data:www-data /var/www/html
systemctl restart apache2

echo "如果不存在，则创建 options-ssl-apache.conf 文件..."
if [ ! -f /etc/letsencrypt/options-ssl-apache.conf ]; then
    mkdir -p /etc/letsencrypt
    bash -c 'printf "SSLEngine on\nSSLProtocol all -SSLv2 -SSLv3\nSSLCipherSuite HIGH:!aNULL:!MD5\nSSLHonorCipherOrder on\nHeader always set Strict-Transport-Security \"max-age=31536000\"\n" > /etc/letsencrypt/options-ssl-apache.conf'
fi
a2enmod headers
systemctl restart apache2

echo "启用 domain https 站点..."
a2ensite "${domain}-le-ssl.conf"
systemctl restart apache2

echo "检查 apache 配置文件语法及服务器运行状态..."
apachectl configtest
systemctl status apache2