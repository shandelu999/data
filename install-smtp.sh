#!/bin/bash

if [ "$(id -u)" -ne 0 ]; then
    echo "已检查到当前为非 root 身份，已中断脚本执行。请以 root 用户身份再次运行此脚本。root 身份获取命令：root -i"
    exit 1
fi

echo "更新系统和安装必要插件..."
apt update
apt upgrade
apt install -y postfix mailutils opendkim opendkim-tools opendmarc certbot python3-certbot libsasl2-2 sasl2-bin libsasl2-modules

# Postfix配置
postconf -e "myhostname = mail.adownoe.store"
postconf -e "mydomain = adownoe.store"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = all"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "relayhost = "
postconf -e "mailbox_size_limit = 0"
postconf -e "recipient_delimiter = +"

# Let's Encrypt证书
certbot certonly --non-interactive --agree-tos --email are361806@gmail.com --preferred-challenges http -d mail.adownoe.store --standalone # 更改Let's Encrypt通知接收邮箱和域名
postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/mail.adownoe.store/fullchain.pem"
postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/mail.adownoe.store/privkey.pem"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_auth_only=yes"

# OpenDKIM配置
mkdir -p /etc/opendkim/keys/adownoe.store
opendkim-genkey -b 2048 -d adownoe.store -D /etc/opendkim/keys/adownoe.store -s mail -v
chown opendkim:opendkim /etc/opendkim/keys/adownoe.store/mail.private
echo "mail._domainkey.adownoe.store adownoe.store:mail:/etc/opendkim/keys/adownoe.store/mail.private" | tee /etc/opendkim/KeyTable
echo "*@adownoe.store mail._domainkey.adownoe.store" | tee /etc/opendkim/SigningTable
echo "127.0.0.1" | tee /etc/opendkim/TrustedHosts
echo "localhost" | tee -a /etc/opendkim/TrustedHosts
echo "adownoe.store" | tee -a /etc/opendkim/TrustedHosts
systemctl restart opendkim

# OpenDMARC配置
echo "AuthservID mail.adownoe.store
Socket local:/var/run/opendmarc/opendmarc.sock
PidFile /var/run/opendmarc/opendmarc.pid
RejectFailures false
Syslog true
TrustedAuthservIDs mail.adownoe.store
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

# sasl配置（让登录用户可以用任意mail from地址发送邮件）
SMTP_SERVER="mail.adownoe.store:587"  # 邮件服务器域名和用来发送邮件的端口
USERNAME="bihande" # 设置用户名
PASSWORD="momobihande" # 设置密码
sh -c "echo '[$SMTP_SERVER] $USERNAME:$PASSWORD' > /etc/postfix/sasl_passwd"
postmap /etc/postfix/sasl_passwd
echo "smtp_sasl_auth_enable = yes
smtpd_recipient_restrictions = permit_sasl_authenticated, reject_unauth_destination
smtpd_sender_restrictions = permit_sasl_authenticated
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt" >> /etc/postfix/main.cf
chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

# 修复postfix service文件ExecStart=参数为：ExecStart=/usr/sbin/postfix start
SERVICE_FILE="/lib/systemd/system/postfix.service"
sed -i 's|^ExecStart=.*|ExecStart=/usr/sbin/postfix start|' $SERVICE_FILE
systemctl daemon-reload
systemctl restart postfix