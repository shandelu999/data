#!/bin/bash

# 变量
domain="awsonling.store"
email="dadanew07559@proton.me"

# 更新软件包索引以检索最新版本软件包
apt update

# 防火墙
apt install -y ufw
ufw enable
ufw allow 22/tcp
ufw allow 25/tcp
ufw allow 587/tcp
ufw allow 465/tcp
ufw allow 80/tcp
ufw reload

# 安装 mailutils 以发送测试邮件
apt install -y mailutils
# 安装 postfix
apt install -y postfix
# 安装 certbot 以申请证书
apt install -y certbot

# 配置 vps 主机名
hostnamectl set-hostname "$domain"

# 配置本地 hosts dns 映射
truncate -s 0 /etc/hosts
tee /etc/hosts > /dev/null <<EOF
127.0.0.1      localhost
::1            localhost         ip6-localhost  ip6-loopback
ff02::1        ip6-allnodes
ff02::2        ip6-allrouters
127.0.1.1      $domain           mail
EOF

# 配置 postfix
postconf -e "inet_interfaces = all"
# 重启 postfix 以生效配置
systemctl restart postfix

# 申请证书
certbot certonly --non-interactive --agree-tos --email $email --preferred-challenges http -d $domain --standalone
# postfix 启用证书
postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/$domain/fullchain.pem"
postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/$domain/privkey.pem"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_security_level=may"
systemctl restart postfix

# openDKIM 安装
apt install -y opendkim opendkim-tools

# 清空 opendkim.conf 原配置
truncate -s 0 /etc/opendkim.conf
# 写入新配置
tee /etc/opendkim.conf > /dev/null <<EOF
LogWhy yes
Syslog yes
SyslogSuccess yes
PidFile /run/opendkim/opendkim.pid
UserID opendkim
UMask 007
Mode sv
Socket inet:8891@127.0.0.1
KeyTable /etc/opendkim/KeyTable
SigningTable refile:/etc/opendkim/SigningTable
ExternalIgnoreList refile:/etc/opendkim/TrustedHosts
InternalHosts refile:/etc/opendkim/TrustedHosts
Canonicalization relaxed/simple
OversignHeaders From
RequireSafeKeys False
EOF

# 新建 /etc/opendkim 目录
mkdir -p /etc/opendkim 

# 配置 SigningTable 以定义需要进行 dkim 签名的发件人地址
echo "*@$domain mail._domainkey.$domain" > /etc/opendkim/SigningTable

# 配置 KeyTable 以指定：DKIM 密钥的存储位置，并关联到对应的域名和选择器（selector）
echo "mail._domainkey.$domain $domain:mail:/etc/opendkim/keys/$domain/mail.private" > /etc/opendkim/KeyTable

# 配置 TrustedHosts 以指定：仅签发 dkim 签名但不进行签名验证的主机
truncate -s 0 /etc/opendkim/TrustedHosts
tee /etc/opendkim/TrustedHosts > /dev/null <<EOF
127.0.0.1
::1
$domain
*.$domain
EOF

# 创建 dkim 公私钥存放目录
mkdir -p /etc/opendkim/keys/$domain

# 生成公私钥
opendkim-genkey -b 2048 -d $domain -D /etc/opendkim/keys/$domain -s mail -v

# 使 opendkim 成为密钥所有者
chown opendkim:opendkim /etc/opendkim/keys -R

# 赋予 /etc/opendkim 目录下的文件夹和文件对应权限
chown -R opendkim:opendkim /etc/opendkim
find /etc/opendkim -type d -exec chmod 700 {} \;
find /etc/opendkim -type f -exec chmod 600 {} \;

# 重启 openDKIM 以生效配置
systemctl restart opendkim

# 配置 main.cf 以让 postfix 通过 milter 协议调用 openDKIM
postconf -e "smtpd_milters = inet:127.0.0.1:8891"
postconf -e "non_smtpd_milters = inet:127.0.0.1:8891"
postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"

# 重启以生效
systemctl restart opendkim
systemctl restart postfix

# 显示公钥
cat /etc/opendkim/keys/$domain/mail.txt