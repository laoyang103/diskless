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

# 与用户交互选择绑定网卡
num=1
nicList=$(ip a | grep state | awk -F ":" '{print $2}' | sed "s/ //g")
for nic in ${nicList[@]}; do
  ipnet=$(ip a | grep -w $nic | grep scope | awk '{print $2}')
  echo "$num: $nic $ipnet"
  num=$(echo $num + 1 | bc)
done
read -p "请根据序号选择要绑定的网卡：" select
selectip=$(ip a | grep scope | grep -v inet6 | sed -n $select"p" | awk '{print $2}')
echo "你选择的网卡IP地址为：$selectip"

# 计算用户选择网卡的网络地址和子网掩码
network=$(ipcalc -n $selectip | awk -F "=" '{print $2}')
netmask=$(ipcalc -m $selectip | awk -F "=" '{print $2}')

# 计算用户选择网卡的可用IP地址范围
IFS=. read -r i1 i2 i3 i4 <<< "$network"
IFS=. read -r m1 m2 m3 m4 <<< "$netmask"
net=$(( (i1 << 24) + (i2 << 16) + (i3 << 8) + i4 ))
mask=$(( (m1 << 24) + (m2 << 16) + (m3 << 8) + m4 ))
hostmin=$(( (net & mask) + 1 ))
hostmax=$(( ((net & mask) | (~mask & 0xffffffff)) - 1 ))
printf '可用IP地址范围是：%d.%d.%d.%d-%d.%d.%d.%d\n' $((hostmin >> 24)) $(( (hostmin >> 16) & 255 )) $(( (hostmin >> 8) & 255 )) $(( hostmin & 255 )) $((hostmax >> 24)) $(( (hostmax >> 16) & 255 )) $(( (hostmax >> 8) & 255 )) $(( hostmax & 255 ))

# 用户客户端的网络参数
read -p "请输入起始IP地址：" begin
read -p "请输入结束IP地址：" end
read -p "请输入客户端网关地址：" gateway

# 配置DHCP网络参数
ipaddr=$(echo $selectip | awk -F "/" '{print $1}')
cat > /etc/dhcp/dhcpd.conf << EOF
default-lease-time 600;
max-lease-time 7200;
subnet $network netmask $netmask {
  range $begin $end;
  option routers $gateway;
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
