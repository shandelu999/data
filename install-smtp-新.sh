#!/bin/bash

domain="awsonling.store"                   # 邮件服务器域名
hostname="mail.$domain"
email="dadanew07559@proton.me"             # Let's Encrypt 证书通知邮箱
smtp_server="$hostname:587"                # 邮件服务器端口
username="bihande"                         # smtp 登录用户名
password="momobihande"                     # smtp 登录密码
opendkim_dir="/etc/opendkim/keys/$domain"

if [ "$(id -u)" -ne 0 ]; then
    echo "已检查到当前为非 root 身份，已中断脚本执行。请以 root 用户身份再次运行此脚本。root 身份获取命令：root -i"
    exit 1
fi

echo "更新系统和安装必要插件..."
apt update
apt upgrade -y
apt install -y postfix mailutils opendkim opendkim-tools opendmarc certbot python3-certbot libsasl2-2 sasl2-bin libsasl2-modules

echo "打开防火墙相应入站端口..."
ufw enable
ufw allow 25/tcp
ufw allow 587/tcp
ufw allow 465/tcp
ufw allow 110/tcp
ufw allow 995/tcp
ufw allow 143/tcp
ufw allow 993/tcp
ufw allow 80/tcp
ufw reload
echo "防火墙入站端口 22 443 53 均以打开..."

echo "配置 postfix..."
postconf -e "myhostname = $hostname"
postconf -e "mydomain = $domain"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = all"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "relayhost = "
postconf -e "mailbox_size_limit = 0"
postconf -e "recipient_delimiter = +"

echo "申请 Let's Encrypt 证书..."
certbot certonly --non-interactive --agree-tos --email $email --preferred-challenges http -d $hostname --standalone
postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/$hostname/fullchain.pem"
postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/$hostname/privkey.pem"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_auth_only=yes"

echo "配置 OpenDKIM..."
mkdir -p $opendkim_dir
opendkim-genkey -b 2048 -d $domain -D $opendkim_dir -s mail -v
chown opendkim:opendkim $opendkim_dir/mail.private
echo "mail._domainkey.$domain $domain:mail:$opendkim_dir/mail.private" | tee /etc/opendkim/KeyTable
echo "*@$domain mail._domainkey.$domain" | tee /etc/opendkim/SigningTable
echo "127.0.0.1" | tee /etc/opendkim/TrustedHosts
echo "localhost" | tee -a /etc/opendkim/TrustedHosts
echo "$domain" | tee -a /etc/opendkim/TrustedHosts
systemctl restart opendkim

echo "配置 OpenDMARC..."
echo "AuthservID $hostname
Socket local:/var/run/opendmarc/opendmarc.sock
PidFile /var/run/opendmarc/opendmarc.pid
RejectFailures false
Syslog true
TrustedAuthservIDs $hostname
IgnoreHosts /etc/opendmarc/ignore.hosts
HistoryFile /var/run/opendmarc/opendmarc.dat" | tee /etc/opendmarc.conf
chown opendmarc:opendmarc /run/opendmarc
chmod 0755 /run/opendmarc
mkdir -p /etc/opendmarc/
touch /etc/opendmarc/ignore.hosts
echo "localhost" | tee /etc/opendmarc/ignore.hosts
echo "127.0.0.1" | tee -a /etc/opendmarc/ignore.hosts
chown opendmarc:opendmarc /etc/opendmarc/ignore.hosts
chown opendmarc:opendmarc /etc/opendmarc.conf
systemctl restart opendmarc

echo "配置 sasl 以验证 smtp 使用者身份..."
sh -c "echo '[$smtp_server] $username:$password' > /etc/postfix/sasl_passwd"
postmap /etc/postfix/sasl_passwd
echo "smtp_sasl_auth_enable = yes
smtpd_recipient_restrictions = permit_sasl_authenticated, reject_unauth_destination
smtpd_sender_restrictions = permit_sasl_authenticated
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt" >> /etc/postfix/main.cf
chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

echo "修复 postfix service 文件的 ExecStart= 参数..."
service_file="/lib/systemd/system/postfix.service"
sed -i 's|^ExecStart=.*|ExecStart=/usr/sbin/postfix start|' $service_file
systemctl daemon-reload
systemctl restart postfix