#!/bin/bash

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

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 用户身份运行此脚本！"
    exit 1
fi

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

# 申请 Let's Encrypt 证书
certbot certonly --non-interactive --agree-tos --email $email --preferred-challenges http -d $mail_domain --standalone
postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/$mail_domain/fullchain.pem"
postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/$mail_domain/privkey.pem"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_auth_only=yes"
systemctl restart postfix

# 配置 postfix main.cf 文件
postconf -e "myhostname = $mail_domain"
postconf -e "mydomain = $domain"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = all"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "mailbox_size_limit = 0"
postconf -e "recipient_delimiter = +"
postconf -e "smtp_sasl_auth_enable = yes"
postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
postconf -e "smtp_sasl_security_options = noanonymous"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_tls_auth_only = yes"
systemctl restart postfix

# 配置 postfix master.cf 文件
sed -i '/^#submission inet n/ s/^#//' /etc/postfix/master.cf
sed -i '/^submission inet n/a \ \ -o smtpd_tls_security_level=encrypt' /etc/postfix/master.cf
sed -i '/^submission inet n/a \ \ -o smtpd_sasl_auth_enable=yes' /etc/postfix/master.cf
sed -i '/^submission inet n/a \ \ -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject' /etc/postfix/master.cf
sed -i '/^submission inet n/a \ \ -o smtpd_tls_auth_only=yes' /etc/postfix/master.cf
systemctl restart postfix

# 配置 OpenDKIM
mkdir -p $opendkim_dir
opendkim-genkey -b 2048 -d $mail_domain -D $opendkim_dir -s mail -v
chown opendkim:opendkim $opendkim_dir/mail.private

# 使用 sed 修改或追加 OpenDKIM 配置
conf_file="/etc/opendkim.conf"
sed -i '/^Socket\s\+/c\Socket                  inet:127.0.0.1:8891' $conf_file
grep -q '^KeyTable' $conf_file || echo "KeyTable                /etc/opendkim/KeyTable" >> $conf_file
grep -q '^SigningTable' $conf_file || echo "SigningTable            /etc/opendkim/SigningTable" >> $conf_file
grep -q '^TrustedHosts' $conf_file || echo "TrustedHosts            /etc/opendkim/TrustedHosts" >> $conf_file
grep -q '^LogWhy' $conf_file || echo "LogWhy                  Yes" >> $conf_file
grep -q '^Canonicalization' $conf_file || echo "Canonicalization        relaxed/simple" >> $conf_file
grep -q '^Selector' $conf_file || echo "Selector                mail" >> $conf_file
grep -q '^Domain' $conf_file || echo "Domain                  $mail_domain" >> $conf_file

# 配置 OpenDKIM 的文件
echo "mail._domainkey.$mail_domain $mail_domain:mail:$opendkim_dir/mail.private" > /etc/opendkim/KeyTable
echo "*@$mail_domain mail._domainkey.$mail_domain" > /etc/opendkim/SigningTable
echo "127.0.0.1" > /etc/opendkim/TrustedHosts
echo "localhost" >> /etc/opendkim/TrustedHosts
echo "$mail_domain" >> /etc/opendkim/TrustedHosts

# 配置 postfix 和 OpenDKIM 的集成
postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"
postconf -e "smtpd_milters = inet:127.0.0.1:8891"
postconf -e "non_smtpd_milters = inet:127.0.0.1:8891"

# 配置 SASL 验证
echo "[$smtp_server] $smtp_username:$smtp_password" > /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

# 重启服务顺序
systemctl restart opendkim
systemctl restart postfix

# 显示 DKIM 公钥
echo "postfix 部署完成，DKIM 公钥如下："
echo "----------------------------------------------------------------------"
cat /etc/opendkim/keys/$mail_domain/mail.txt
echo "----------------------------------------------------------------------"