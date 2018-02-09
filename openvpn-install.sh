#!/bin/bash

PORT=10749
OS="unsupported"
if [[ "$EUID" -ne 0 ]]; then echo "Sorry, you need to run this as root";exit 1; fi
if [[ ! -e /dev/net/tun ]]; then echo "TUN is not available";exit 2; fi
if grep -qs "CentOS Linux release 7" "/etc/redhat-release"; then echo "CentOS 7 Supported";OS="centos";fi
if grep -qs "CentOS Linux release 6" "/etc/redhat-release"; then echo "CentOS 6 Supported";OS="centos";fi

if [[ "$OS" = 'centos' ]]; then
SERVER_CN="cn_$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
SERVER_NAME="server_$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
yum install epel-release -y
yum install openvpn iptables openssl wget ca-certificates curl -y
rm -rf /etc/openvpn/easy-rsa/
wget -O ~/EasyRSA-3.0.4.tgz https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.4/EasyRSA-3.0.4.tgz
tar xzf ~/EasyRSA-3.0.4.tgz -C ~/
rm -rf ~/EasyRSA-3.0.4.tgz
mv ~/EasyRSA-3.0.4 /etc/openvpn/easy-rsa
chown -R root:root /etc/openvpn/easy-rsa/
cd /etc/openvpn/easy-rsa/
./easyrsa init-pki
./easyrsa --batch build-ca nopass
./easyrsa gen-dh
./easyrsa build-server-full $SERVER_NAME nopass
EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
openvpn --genkey --secret /etc/openvpn/tls-auth.key
cp pki/ca.crt pki/private/ca.key pki/dh.pem pki/issued/$SERVER_NAME.crt pki/private/$SERVER_NAME.key /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
chmod 644 /etc/openvpn/crl.pem

cat > /etc/openvpn/server.conf <<EOF
port $PORT
proto tcp
dev tun
user nobody
group nobody
persist-key
persist-tun
keepalive 10 120
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
push "redirect-gateway def1 bypass-dhcp"
crl-verify crl.pem
ca ca.crt
cert $SERVER_NAME.crt
key $SERVER_NAME.key
tls-auth tls-auth.key 0
dh dh.pem
auth SHA256
cipher AES-256-CBC
tls-server
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
status openvpn.log
verb 3
EOF

NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $NIC -j MASQUERADE
if pgrep systemd-journal; then
	systemctl restart openvpn@server.service
	systemctl enable openvpn@server.service
else
	service openvpn start
	chkconfig openvpn on
fi
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i '/\<net.ipv4.ip_forward\>/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
	
#create a client
CLIENT_NAME="client_$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"
./easyrsa build-client-full $CLIENT_NAME nopass
IP=$(wget -qO- ipv4.icanhazip.com)
CA_Content=`cat /etc/openvpn/easy-rsa/pki/ca.crt`
CCERT_Content=`cat /etc/openvpn/easy-rsa/pki/issued/$CLIENT_NAME.crt`
CKEY_Content=`cat /etc/openvpn/easy-rsa/pki/private/$CLIENT_NAME.key`
TLSAUTH_Content=`cat /etc/openvpn/tls-auth.key`

cat > /etc/openvpn/$CLIENT_NAME.ovpn <<EOF
client
proto tcp-client
remote $IP $PORT
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
verify-x509-name $SERVER_NAME name
auth SHA256
auth-nocache
cipher AES-256-CBC
tls-client
tls-version-min 1.2
tls-cipher TLS-DHE-RSA-WITH-AES-128-GCM-SHA256
setenv opt block-outside-dns
verb 3
<ca>
$CA_Content
</ca>
<cert>
$CCERT_Content
</cert>
<key>
$CKEY_Content
</key>
key-direction 1
<tls-auth>
$TLSAUTH_Content
</tls-auth>
EOF

fi