#!/bin/bash

# 检查操作系统版本
echo "实测该脚本能完美运行于 Debian 12 系统。"
read -p "当前系统是否为 Debian 12？是就输入 y 继续执行脚本，否则输入 n 终止脚本: " is_debian_12
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
smtp_server="$mail_domain:587"                  # 客户端向本 SMTP 服务器提交邮件的域名和端口
smtp_username="bihande"                         # 客户端登陆 SMTP 服务器的用户名
smtp_password="momobihande"                     # 客户端登陆 SMTP 服务器的密码
dkim_key_dir="/etc/dkimpy-milter/keys/$mail_domain"  # DKIM 密钥存放路径

# 修改 VPS 主机名
hostnamectl set-hostname "$mail_domain"

# 安装必要的软件包
apt update
apt install -y python3 python3-pip python3-dkimpy python3-venv libsasl2-2 sasl2-bin libsasl2-modules mailutils postfix certbot ufw

# 安装 dkimpy-milter
pip3 install dkimpy-milter

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

# 配置 DKIM
mkdir -p "$dkim_key_dir"
dkimpy-milter-keygen --domain "$mail_domain" --selector mail --directory "$dkim_key_dir"
chown -R postfix:postfix "$dkim_key_dir"
chmod -R 600 "$dkim_key_dir"

cat <<EOT > /etc/dkimpy-milter/dkimpy-milter.conf
# DKIMpy-Milter 配置文件
Socket                  inet:8891@localhost
KeyTable                refile:$dkim_key_dir/keytable
SigningTable            refile:$dkim_key_dir/signingtable
LogResults              true
Canonicalization        relaxed/simple
Selector                mail
Domain                  $mail_domain
EOT

# 配置 KeyTable 和 SigningTable
echo "mail._domainkey.$mail_domain $mail_domain:mail:$dkim_key_dir/mail.private" > "$dkim_key_dir/keytable"
echo "*@$mail_domain mail._domainkey.$mail_domain" > "$dkim_key_dir/signingtable"

# 配置 Postfix 集成 DKIMpy-Milter
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 6"
postconf -e "smtpd_milters = inet:localhost:8891"
postconf -e "non_smtpd_milters = inet:localhost:8891"
systemctl restart postfix

# 启动 DKIMpy-Milter
dkimpy-milter --config /etc/dkimpy-milter/dkimpy-milter.conf --daemonize

echo "DKIM 公钥:"
cat "$dkim_key_dir/mail.txt"
echo "请将以上 DKIM 公钥添加到 DNS TXT 记录中，Host 为 mail._domainkey.$mail_domain。"