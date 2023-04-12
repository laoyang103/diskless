#!/bin/bash

# 保证客户端操作系统存在
if [ ! -e "win8pe.iso" ]; then
  echo "未检测到客户端系统win8pe.iso"
  echo "请将客户端的启动镜像放到与安装脚本install.sh同一目录下，并命名为win8pe.iso"
  echo "如果自己没有可以到http://192.168.10.254:8080/iso/winpe/win8pe.iso去下载"
  exit
fi

# 离线安装所需要软件包
yum -y install rpms/*.rpm

# 配置DHCP网络参数
ipaddr=$(ip a | grep "scope global" | head -n 1 | awk '{print $2}' | awk -F "/" '{print $1}')
cat > /etc/dhcp/dhcpd.conf << EOF
default-lease-time 600;
max-lease-time 7200;
subnet 10.10.10.0 netmask 255.255.255.0 {
  range 10.10.10.100 10.10.10.200;
  option routers 10.10.10.254;
  option domain-name-servers $ipaddr;
  next-server $ipaddr;
  filename "lpxelinux.0";
}
EOF

# 替换tftp配置文件中disable=no
sed -i 's/disable\t\t\t= yes/disable\t\t\t= no/g' /etc/xinetd.d/tftp

tftpPath="/var/lib/tftpboot"
# 解压启动引导程序到tftp目录
tar -zxf syslinux.tar.gz -C $tftpPath
mv $tftpPath/syslinux604files/* $tftpPath

# 移动win8pe镜像到/var/ftp/pub目录
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

# 开启samba匿名访问
sed -i '9i\'$'\t''map to guest = bad user' /etc/samba/smb.conf
# 创建game共享项
cat >> /etc/samba/smb.conf << EOF
[game]
	comment = some games
	path = /var/lib/samba/game
	guest ok = Yes
EOF

# 创建/var/lib/samba/game目录
gamepath="/var/lib/samba/game"
mkdir -p $gamepath

# 下载八数码游戏EIGHT.zip，解压到/var/lib/samba/game
unzip EIGHT.zip -d $gamepath

# 给游戏可执行程序EIGHT.exe执行权限
chmod +x $gamepath/EIGHT/EIGHT.exe

# 配置DNS的主配置文件，允许外部访问
sed -i "s/127.0.0.1/any/g" /etc/named.conf
sed -i "s/::1/any/g" /etc/named.conf
sed -i "s/localhost/any/g" /etc/named.conf

# 定义域名空间qq.com
cat >> /etc/named.rfc1912.zones << EOF
zone "qq.com" IN {
        type master;
        file "named.qq.com";
        allow-update { none; };
};
EOF

# 定义qq.com域名空间的解析记录
cat > /var/named/named.qq.com << EOF
\$TTL 1D
@	IN SOA	@ rname.invalid. (
					0	; serial
					1D	; refresh
					1H	; retry
					1W	; expire
					3H )	; minimum
	NS	@
	A	127.0.0.1
www	A	$ipaddr
bbs	A	$ipaddr
	AAAA	::1
EOF

# 创建网站首页index.html，内容为nononono
echo "nononono" > /var/www/html/index.html

# 启动各种服务，关闭防火墙和selinux
svcList=("dhcpd" "xinetd" "vsftpd" "smb" "named" "httpd")
for svc in ${svcList[@]}; do
  systemctl restart $svc
done
systemctl stop firewalld
setenforce 0
