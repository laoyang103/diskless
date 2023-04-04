#!/bin/bash

# 安装所需要软件包
yum -y install dhcp xinetd tftp-server vsftpd wget 

# 配置DHCP网络参数
ipaddr=$(ip a | grep "scope global" | head -n 1 | awk '{print $2}' | awk -F "/" '{print $1}')
cat > /etc/dhcp/dhcpd.conf << EOF
default-lease-time 600;
max-lease-time 7200;
subnet 10.10.10.0 netmask 255.255.255.0 {
  range 10.10.10.100 10.10.10.200;
  option routers 10.10.10.254;
  option domain-name-servers 114.114.114.114;
  next-server $ipaddr;
  filename "lpxelinux.0";
}
EOF

# 替换tftp配置文件中disable=no
sed -i 's/disable\t\t\t= yes/disable\t\t\t= no/g' /etc/xinetd.d/tftp

tftpPath="/var/lib/tftpboot"
# 下载启动引导程序，解压到tftp目录
wget http://192.168.10.254:8080/jxfiles/syslinux.tar.gz
tar -zxf syslinux.tar.gz -C $tftpPath
mv $tftpPath/syslinux604files/* $tftpPath

# 下载win8pe镜像到/var/ftp/pub目录
wget http://192.168.10.254:8080/iso/winpe/win8pe.iso
mv win8pe.iso /var/ftp/pub

# 创建启动菜单文件
mkdir -p $tftpPath/pxelinux.cfg
cat > $tftpPath/pxelinux.cfg/default << EOF
DEFAULT menu.c32
TIMEOUT 30

LABEL win8pe
  KERNEL memdisk
  APPEND initrd=ftp://\${next-server}/pub/win8pe.iso iso raw
EOF

# 启动各种服务，关闭防火墙和selinux
svcList=("dhcpd" "xinetd" "vsftpd")
for svc in ${svcList[@]}; do
  systemctl restart $svc
done
systemctl stop firewalld
setenforce 0
