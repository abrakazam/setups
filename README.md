# update of system (if your system is not updated)
if grep -qs "CentOS" "/etc/redhat-release"; then echo "CentOS";PM="yum";fi
if grep -qs "^8.\|^7." "/etc/debian_version"; then echo "Debian";PM="apt-get";fi
echo $PM;$PM update -y;$PM install ca-certificates -y;

# setups
wget https://raw.githubusercontent.com/abrakazam/setups/master/openvpn-install.sh;bash openvpn-install.sh

# Tested
Debian 8 x64
Debian 7 x86/x64
CentOS 7 x64
CentOS 6 x86/x64