#!/bin/bash

# openDKIM 的配置及其敏感，包括：安装时机、套接字、关联软件（mailutils、postfix、certbot）安装顺序、等等。错一个，全盘错。
# 脚本部署后发件人为根域 @awsonling.store。如要调整发件人为子域 @mail.awsonling.store，重新做一个新脚本。
# 脚本已实现自动续订证书

# 变量
domain="awsonling.store"  # @ 符号右侧部分。也是根域名。也是发件人域名
local_part="support"  # @ 符号左侧的部分。也是本地客户端登陆本 smtp 服务器时的用户名
mail_from="$local_part@$domain"  # 邮件发送地址
display_name="Support" # 邮件显示名。如：“Support <support@awsonling.store>”中的第一个 Support。收件人在邮件客户端中通常会优先看到 显示名，而不是纯粹的邮箱地址
crt_email="dadanew07559@proton.me"  # 申请证书时的邮箱
password="areyoushande"  # 本地客户端登陆本 smtp 服务器时的密码（部署中涉及的其他密码，都是这个）

# 更新软件包索引以检索最新版本软件包
apt update

# 防火墙配置
apt install -y ufw
ufw allow OpenSSH   # 启用 ufw 前，确保 ssh 连接不会被阻断
ufw allow 25/tcp    # smtp
ufw allow 80/tcp    # http
ufw allow 443/tcp   # https（如果需要）
ufw allow 465/tcp   # smtps
ufw allow 587/tcp   # smtp submission
ufw allow 993/tcp   # imaps
ufw allow 995/tcp   # pop3s
ufw --force enable
ufw reload

# 安装必要的软件包
apt install -y mailutils postfix certbot opendkim opendkim-tools dovecot-core dovecot-imapd dovecot-pop3d
                                             
# 配置 vps 主机名
hostnamectl set-hostname "$domain"

# 配置本地 hosts DNS 映射
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
postconf -e "myhostname = $domain"
postconf -e "home_mailbox = Maildir/"
# 重启 postfix 以生效配置
systemctl restart postfix

# 申请证书
certbot certonly --non-interactive --agree-tos --email $crt_email --preferred-challenges http -d $domain --standalone

# postfix 启用证书
postconf -e "smtpd_tls_cert_file=/etc/letsencrypt/live/$domain/fullchain.pem"
postconf -e "smtpd_tls_key_file=/etc/letsencrypt/live/$domain/privkey.pem"
postconf -e "smtpd_use_tls=yes"
postconf -e "smtpd_tls_security_level=may"
systemctl restart postfix

# openDKIM 配置

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

# 配置 KeyTable 以指定 dkim 密钥的存储位置，并关联到对应的域名和选择器（selector）
echo "mail._domainkey.$domain $domain:mail:/etc/opendkim/keys/$domain/mail.private" > /etc/opendkim/KeyTable

# 配置 TrustedHosts 以指定仅签发 dkim 签名但不进行签名验证的主机
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

# 设置 openDKIM 密钥所有者和权限
chown -R opendkim:opendkim /etc/opendkim/keys/$domain
find /etc/opendkim/keys/$domain -type d -exec chmod 700 {} \;
find /etc/opendkim/keys/$domain -type f -exec chmod 600 {} \;

# 重启 openDKIM 以生效配置
systemctl restart opendkim

# 配置 postfix 以通过 milter 协议调用 openDKIM
postconf -e "smtpd_milters = inet:127.0.0.1:8891"
postconf -e "non_smtpd_milters = inet:127.0.0.1:8891"
postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"

# 重启服务以应用 openDKIM 配置
systemctl restart opendkim
systemctl restart postfix

# 配置 SASL 以启用本地客户端连接本服务器发送和接收邮件

# 配置 /etc/dovecot/conf.d/10-master.conf
truncate -s 0 /etc/dovecot/conf.d/10-master.conf
truncate -s 0 /etc/dovecot/conf.d/10-master.conf
tee /etc/dovecot/conf.d/10-master.conf > /dev/null <<EOF
# IMAP 登录服务
service imap-login {
  inet_listener imap {
    port = 0
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}

# POP3 登录服务
service pop3-login {
  inet_listener pop3 {
    port = 0
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}

# 认证服务
service auth {
  unix_listener auth-userdb {
    mode = 0600
    user = dovecot
    group = dovecot
  }
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
}

# LMTP 服务（用于邮件投递）
service lmtp {
  unix_listener /var/spool/postfix/private/lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

# IMAP 服务
service imap {
}

# POP3 服务
service pop3 {
}

# 认证工作进程
service auth-worker {
  # 默认配置
}

# 字典服务
service dict {
  unix_listener dict {
    # 默认配置
  }
}
EOF

# 修改 /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^auth_mechanisms = .*/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf

# 配置邮箱位置
sed -i 's|^#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf

# 配置 SSL
sed -i 's/^#ssl = yes/ssl = required/' /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^#ssl_cert =.*|ssl_cert = </etc/letsencrypt/live/$domain/fullchain.pem|" /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^#ssl_key =.*|ssl_key = </etc/letsencrypt/live/$domain/privkey.pem|" /etc/dovecot/conf.d/10-ssl.conf

# 配置用户数据库
echo "passdb {" >> /etc/dovecot/conf.d/10-auth.conf
echo "  driver = pam" >> /etc/dovecot/conf.d/10-auth.conf
echo "}" >> /etc/dovecot/conf.d/10-auth.conf
echo "userdb {" >> /etc/dovecot/conf.d/10-auth.conf
echo "  driver = passwd" >> /etc/dovecot/conf.d/10-auth.conf
echo "}" >> /etc/dovecot/conf.d/10-auth.conf

# 创建邮件用户并设置密码
useradd -m -s /usr/sbin/nologin $local_part
echo "$local_part:$password" | chpasswd

# 创建 Maildir 目录，并赋权
mkdir -p /home/$local_part/Maildir/{cur,new,tmp}
chown -R $local_part:$local_part /home/$local_part/Maildir
chmod -R 700 /home/$local_part/Maildir

# 配置 postfix 使用 dovecot 进行 SASL 认证
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_security_options = noanonymous"
postconf -e "smtpd_sasl_local_domain = \$myhostname"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"
postconf -e "smtpd_sender_restrictions = permit_sasl_authenticated, reject"
postconf -e "mynetworks = 127.0.0.0/8 [::1]/128"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtpd_tls_auth_only = yes"

# 确保 dovecot 有权限读取 SSL 证书
chmod o+x /etc/letsencrypt/live
chmod o+r /etc/letsencrypt/live/$domain/fullchain.pem
chmod o+r /etc/letsencrypt/live/$domain/privkey.pem

# 重启服务以应用配置
systemctl restart postfix
systemctl restart dovecot

# 配置 DNS 记录输出（用户需手动添加）
echo "========================================"
echo "请手动在 DNS 提供商处添加以下记录："
echo ""
echo "1. DKIM TXT 记录（在 mail._domainkey.$domain）:"
cat /etc/opendkim/keys/$domain/mail.txt
echo ""
echo "2. SPF TXT 记录（在 $domain）:"
echo "v=spf1 ip4:xx.xx.xxx.xx ip6:xxxx:xxxx:xx:xxxx::x -all"
echo ""
echo "3. DMARC TXT 记录（在 _dmarc.$domain）:"
echo "v=DMARC1; p=reject; rua=mailto:postmaster@$domain"
echo "========================================"

# 配置 SSL 证书的自动续期
systemctl enable certbot.timer
systemctl start certbot.timer



# mail from 更改 support@$domain

# 配置 postfix 使用 maildir 格式
postconf -e "myorigin = \$myhostname"

# 创建 sender_canonical 文件
echo "/.*/ $mail_from" > /etc/postfix/sender_canonical

# 设置文件权限
chmod 644 /etc/postfix/sender_canonical
chown root:root /etc/postfix/sender_canonical

# 生成 postfix 可识别的映射数据库
postmap /etc/postfix/sender_canonical

# 更新 postfix 配置
postconf -e "sender_canonical_maps = regexp:/etc/postfix/sender_canonical"

# 重启 postfix
systemctl restart postfix

# display name 显示名更改
# 由于本 smtp 的 mail from = from，因此仅更改显示名即可。否则，应该更改 /etc/postfix/generic 文件 <$local_part@$domain> 里的 $domain 部分，增加变量 $sub_domain。并重新进行 DKIM 和 DMARC。

# 生成 /etc/postfix/generic 文件
echo "root@$domain $display_name <$local_part@$domain>" > /etc/postfix/generic

# 生成 Postfix 可识别的映射数据库
postmap /etc/postfix/generic

# 设置文件权限和所有者
chmod 644 /etc/postfix/generic
chown root:root /etc/postfix/generic
chmod 600 /etc/postfix/generic.db
chown root:root /etc/postfix/generic.db

# 更新 Postfix 配置以使用 generic_maps
postconf -e "smtp_generic_maps = hash:/etc/postfix/generic"

# 重启 Postfix 以应用更改
systemctl restart postfix

echo "邮件服务器部署完毕"
echo "mail from = $local_part@$domain"
echo "from = $display_name <$local_part@$domain>"