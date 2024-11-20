#!/bin/bash

# 检查操作系统版本
echo "实测该脚本能完美运行于 Debian 12 系统。"
read -p "当前系统是否为 Debian 12 ？是就输入 y 继续执行脚本，否则输入 n 终止脚本: " is_debian_12
if [[ "$is_debian_12" != "y" ]]; then
    echo "脚本已终止，请在 Debian 12 系统上运行此脚本。"
    exit 1
fi

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 用户身份运行此脚本！"
    exit 1
fi

# 基本变量定义
domain="awsonling.store"                        # 服务器根域名
mail_domain="mail.$domain"                      # 邮件服务器的完整子域名（FQDN）
email="dadanew07559@proton.me"                  # Let's Encrypt 证书通知邮箱
smtp_server="$mail_domain:587"                  # 客户端向本 smtp 服务器提交邮件的域名和端口
smtp_username="bihande"                         # 客户端登陆 smtp 服务器的用户名
smtp_password="momobihande"                     # 客户端登陆 smtp 服务器的密码
opendkim_dir="/etc/opendkim/keys/$mail_domain"

# 修改 VPS 主机名
hostnamectl set-hostname "$mail_domain"

# 安装必要的软件包
apt install -y ufw postfix mailutils opendkim opendkim-tools certbot python3-certbot libsasl2-2 sasl2-bin libsasl2-modules

# 配置防火墙
ufw enable
ufw allow 22/tcp
ufw allow 25/tcp
ufw allow 587/tcp
ufw allow 465/tcp
ufw allow 110/tcp
ufw allow 995/tcp
ufw allow 143/tcp
ufw allow 993/tcp
ufw allow 80/tcp
ufw reload

# 为根域名申请 TLS 证书
certbot certonly --non-interactive --agree-tos --email $email --preferred-challenges http -d $domain --standalone
# 为邮件子域名申请 TLS 证书
certbot certonly --non-interactive --agree-tos --email $email --preferred-challenges http -d $mail_domain --standalone
# 更新邮件服务器 TLS 证书路径（支持根域名和邮件子域名）
postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/$mail_domain/fullchain.pem"
postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/$mail_domain/privkey.pem"
postconf -e "smtp_tls_cert_file=/etc/letsencrypt/live/$domain/fullchain.pem"
postconf -e "smtp_tls_key_file=/etc/letsencrypt/live/$domain/privkey.pem"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_auth_only=yes"
# 重启 Postfix 服务以应用新配置
systemctl restart postfix

# 配置 OpenDKIM
mkdir -p $opendkim_dir
opendkim-genkey -b 2048 -d $mail_domain -D $opendkim_dir -s mail -v
chown opendkim:opendkim $opendkim_dir/*
chmod 600 $opendkim_dir/*

# 确保 /run/opendkim 目录存在
mkdir -p /run/opendkim
chown opendkim:opendkim /run/opendkim
chmod 750 /run/opendkim

# 覆盖 /etc/opendkim.conf 主配置文件
cat <<EOT > /etc/opendkim.conf
Syslog                  yes
LogWhy                  yes
Canonicalization        relaxed/simple
ExternalIgnoreList      /etc/opendkim/TrustedHosts
InternalHosts           /etc/opendkim/TrustedHosts
KeyTable                /etc/opendkim/KeyTable
SigningTable            /etc/opendkim/SigningTable
Socket                  local:/run/opendkim/opendkim.sock
UserID                  opendkim
PidFile                 /run/opendkim/opendkim.pid
Mode                    sv
OversignHeaders         From
EOT

# 配置 /etc/opendkim/ 目录下的辅助文件（KeyTable、SigningTable、TrustedHosts）
echo "mail._domainkey.$mail_domain $mail_domain:mail:$opendkim_dir/mail.private" > /etc/opendkim/KeyTable
echo "*@$mail_domain mail._domainkey.$mail_domain" > /etc/opendkim/SigningTable
echo "127.0.0.1" > /etc/opendkim/TrustedHosts
echo "localhost" >> /etc/opendkim/TrustedHosts
echo "$mail_domain" >> /etc/opendkim/TrustedHosts

# 配置 postfix 和 OpenDKIM 的集成
postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"
postconf -e "smtpd_milters = local:/run/opendkim/opendkim.sock"
postconf -e "non_smtpd_milters = local:/run/opendkim/opendkim.sock"

# 配置 SASL 验证
echo "[$smtp_server] $smtp_username:$smtp_password" > /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

# 重启服务
systemctl daemon-reload
systemctl restart opendkim
systemctl restart postfix

# 显示 DKIM 公钥
echo "postfix 部署完成，DKIM 公钥如下："
echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
cat /etc/opendkim/keys/$mail_domain/mail.txt
echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
