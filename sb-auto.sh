#!/bin/bash
export LANG=en_US.UTF-8
export DEBIAN_FRONTEND=noninteractive
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;36m'
bblue='\033[0;34m'
plain='\033[0m'
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ if [[ "$AUTO" == "1" ]]; then yellow "$1(自动选择默认)"; eval "$2=''"; else read -r -p "$(yellow "$1")" "$2"; fi;}
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
stty erase $'\b' 2>/dev/null || stty erase '^H' 2>/dev/null
# 统一的 JSON 读写辅助函数（替代硬编码行号 sed，支持去 // 注释并原子写入）
sbjq_read(){
local f="$1" filter="$2"
[[ -f "$f" ]] || return 1
sed -E 's:(^|[[:space:]])//.*::' "$f" 2>/dev/null | jq -r "$filter" 2>/dev/null
}
sbjq_edit(){
local f="$1"; shift
[[ -f "$f" ]] || return 0
local tmp
tmp=$(mktemp) || return 1
if sed -E 's:(^|[[:space:]])//.*::' "$f" 2>/dev/null | jq "$@" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]] && jq empty "$tmp" >/dev/null 2>&1; then
mv -f "$tmp" "$f"
return 0
else
rm -f "$tmp"
return 1
fi
}
sbjq_edit_all(){
local f
for f in /etc/s-box/sb10.json /etc/s-box/sb11.json /etc/s-box/sb.json; do
[[ -f "$f" ]] && sbjq_edit "$f" "$@"
done
}
sb_has_installed(){
[[ -f '/etc/systemd/system/sing-box.service' || -f '/etc/init.d/sing-box' || -f '/etc/s-box/sb.json' ]]
}
cron_update(){
local del_re="$1" add_line="$2" tmp
tmp=$(mktemp) || return 1
crontab -l 2>/dev/null > "$tmp" || true
[[ -n "$del_re" ]] && sed -i "/$del_re/d" "$tmp"
[[ -n "$add_line" ]] && printf '%s\n' "$add_line" >> "$tmp"
crontab "$tmp" >/dev/null 2>&1
rm -f "$tmp"
}
# 校验是否为合法的 IPv4 地址（4 段 0-255 数字，无多余字符）
is_valid_ipv4(){
local ip="$1" o1 o2 o3 o4
[[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
o1="${BASH_REMATCH[1]}" o2="${BASH_REMATCH[2]}" o3="${BASH_REMATCH[3]}" o4="${BASH_REMATCH[4]}"
(( 10#$o1 <= 255 && 10#$o2 <= 255 && 10#$o3 <= 255 && 10#$o4 <= 255 ))
}
# 校验是否为合法的 IPv6 地址（含冒号且仅包含十六进制字符与冒号）
is_valid_ipv6(){
local ip="$1"
[[ "$ip" == *:* && "$ip" =~ ^[0-9a-fA-F:]+$ ]]
}
# 格式化 host:port，IPv6 自动补充方括号
fmt_host_port(){
local h="$1" p="$2"
if [[ "$h" == *:* && "$h" != \[*\] ]]; then
echo "[$h]:$p"
else
echo "$h:$p"
fi
}
# 纯 IPv6 环境提前配置 NAT64，避免首次安装依赖或拉取 GitHub 失败
ensure_nat64(){
if ! ip -4 route show default 2>/dev/null | grep -q . && ip -6 route show default 2>/dev/null | grep -q .; then
if ! grep -q '2a00:1098:2b::1' /etc/resolv.conf 2>/dev/null; then
local test_v6
test_v6=$(curl -s6 --connect-timeout 2 -m 3 https://icanhazip.com 2>/dev/null | tr -d '[:space:]')
if is_valid_ipv6 "$test_v6"; then
[[ -f /etc/resolv.conf && ! -f /etc/resolv.conf.sb.bak ]] && cp -a /etc/resolv.conf /etc/resolv.conf.sb.bak 2>/dev/null || true
printf 'nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\n' > /etc/resolv.conf
fi
fi
fi
}
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "alpine"; then
release="alpine"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else 
red "脚本不支持当前的系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
export sbfiles="/etc/s-box/sb10.json /etc/s-box/sb11.json /etc/s-box/sb.json"
export sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
op=$(cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | grep -i pretty_name | cut -d \" -f2)
#if [[ $(echo "$op" | grep -i -E "arch|alpine") ]]; then
if [[ $(echo "$op" | grep -i -E "arch") ]]; then
red "脚本不支持当前的 $op 系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
version=$(uname -r | cut -d "-" -f1)
[[ -z $(systemd-detect-virt 2>/dev/null) ]] && vi=$(virt-what 2>/dev/null) || vi=$(systemd-detect-virt 2>/dev/null)
case $(uname -m) in
armv7l) cpu=armv7;;
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "目前脚本不支持$(uname -m)架构" && exit;;
esac
if [[ -n $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk -F ' ' '{print $3}') ]]; then
bbr=`sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}'`
elif [[ -n $(ping 10.0.0.2 -c 2 | grep ttl) ]]; then
bbr="Openvz版bbr-plus"
else
bbr="Openvz/Lxc"
fi
hostname=$(hostname)

mkdir -p /etc/s-box
if [[ -f sbyg_update && ! -f /etc/s-box/.sbyg_update ]]; then
mv -f sbyg_update /etc/s-box/.sbyg_update 2>/dev/null || touch /etc/s-box/.sbyg_update
fi
# 首次运行若为纯 IPv6 环境，提前配置 NAT64 以保障依赖安装与 GitHub 访问
ensure_nat64
if [ ! -f /etc/s-box/.sbyg_update ]; then
green "首次安装Sing-box-yg脚本必要的依赖……"
if command -v apk >/dev/null 2>&1; then
apk update
apk add bash libc6-compat jq openssl procps busybox-extras iproute2 iputils coreutils expect git socat iptables grep tar tzdata util-linux curl wget qrencode python3
apk add ip6tables 2>/dev/null || true
apk add xxd 2>/dev/null || apk add vim 2>/dev/null || true
apk add virt-what 2>/dev/null || true
else
if [[ $release = Centos && ${vsid} =~ 8 ]]; then
cd /etc/yum.repos.d/ && mkdir -p backup && mv *repo backup/ 
curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-8.repo
sed -i -e "s|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g " /etc/yum.repos.d/CentOS-*
sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
yum clean all && yum makecache
cd
fi
if [ -x "$(command -v apt-get)" ]; then
apt update -y
if command -v ufw >/dev/null 2>&1; then
apt install jq cron socat busybox coreutils util-linux -y
else
apt install jq cron socat busybox iptables-persistent coreutils util-linux -y
fi
elif [ -x "$(command -v yum)" ]; then
yum update -y && yum install epel-release -y
yum install jq socat busybox coreutils util-linux -y
elif [ -x "$(command -v dnf)" ]; then
dnf update -y
dnf install jq socat busybox coreutils util-linux -y
fi
if [ -x "$(command -v yum)" ] || [ -x "$(command -v dnf)" ]; then
if systemctl is-active --quiet firewalld 2>/dev/null; then
if [ -x "$(command -v yum)" ]; then
yum install -y cronie
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie
fi
else
if [ -x "$(command -v yum)" ]; then
yum install -y cronie iptables-services
elif [ -x "$(command -v dnf)" ]; then
dnf install -y cronie iptables-services
fi
if ! systemctl is-enabled --quiet iptables 2>/dev/null; then
iptables-save > /etc/sysconfig/iptables 2>/dev/null
ip6tables-save > /etc/sysconfig/ip6tables 2>/dev/null
fi
systemctl enable iptables >/dev/null 2>&1
systemctl start iptables >/dev/null 2>&1
systemctl enable ip6tables >/dev/null 2>&1
systemctl start ip6tables >/dev/null 2>&1
fi
fi
if [[ -z $vi && -x "$(command -v apt-get)" ]]; then
apt-get install iputils-ping iproute2 -y
fi

packages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
inspackages=("curl" "openssl" "iptables" "tar" "expect" "wget" "xxd" "python3" "qrencode" "git")
for i in "${!packages[@]}"; do
package="${packages[$i]}"
inspackage="${inspackages[$i]}"
if ! command -v "$package" &> /dev/null; then
if [ -x "$(command -v apt-get)" ]; then
apt-get install -y "$inspackage" || { [[ "$package" = "xxd" ]] && apt-get install -y vim-common; }
elif [ -x "$(command -v yum)" ]; then
[[ "$package" = "xxd" ]] && inspackage="vim-common"
yum install -y "$inspackage"
elif [ -x "$(command -v dnf)" ]; then
[[ "$package" = "xxd" ]] && inspackage="vim-common"
dnf install -y "$inspackage"
fi
fi
done
fi
touch /etc/s-box/.sbyg_update
fi

if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then 
green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "TUN守护功能已启动"
fi
fi
fi
v4v6(){
# 支持缓存避免同一轮重复探测，传 force 强制刷新；v4/v6 并行探测加速启动
if [[ "$1" != "force" && "$_v4v6_loaded" == "1" ]]; then
return 0
fi
local tmpdir
tmpdir=$(mktemp -d)
(curl -s4 --connect-timeout 2 -m 3 https://icanhazip.com 2>/dev/null || curl -s4 --connect-timeout 2 -m 3 https://api.ipify.org 2>/dev/null) > "$tmpdir/v4" &
(curl -s6 --connect-timeout 2 -m 3 https://icanhazip.com 2>/dev/null || curl -s6 --connect-timeout 2 -m 3 https://api6.ipify.org 2>/dev/null) > "$tmpdir/v6" &
wait
v4=$(tr -d '[:space:]' < "$tmpdir/v4")
v6=$(tr -d '[:space:]' < "$tmpdir/v6")
# 清洗探测结果，避免错误页等非法内容污染 IP 变量
is_valid_ipv4 "$v4" || v4=""
is_valid_ipv6 "$v6" || v6=""
v4dq=""
v6dq=""
# 仅对存在的协议栈查询归属地，单栈 VPS 不再白等另一协议超时
if [[ -n "$v4" ]]; then
curl -s4 --connect-timeout 2 -m 3 https://ip.fm 2>/dev/null | sed -n 's/.*Location: //p' > "$tmpdir/v4dq" &
fi
if [[ -n "$v6" && -z "$v4" ]]; then
curl -s6 --connect-timeout 2 -m 3 https://ip.fm 2>/dev/null | sed -n 's/.*Location: //p' > "$tmpdir/v6dq" &
fi
wait
[[ -f "$tmpdir/v4dq" ]] && v4dq=$(cat "$tmpdir/v4dq")
[[ -f "$tmpdir/v6dq" ]] && v6dq=$(cat "$tmpdir/v6dq")
rm -rf "$tmpdir"
_v4v6_loaded=1
}
warpcheck(){
local tmpdir
tmpdir=$(mktemp -d)
curl -s6 --connect-timeout 2 -m 4 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep '^warp=' | cut -d= -f2 > "$tmpdir/w6" &
curl -s4 --connect-timeout 2 -m 4 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | grep '^warp=' | cut -d= -f2 > "$tmpdir/w4" &
wait
wgcfv6=$(cat "$tmpdir/w6")
wgcfv4=$(cat "$tmpdir/w4")
rm -rf "$tmpdir"
}

v6(){
v4orv6(){
local has_v4 has_v6
has_v4=$(curl -s4 --connect-timeout 2 -m 4 https://icanhazip.com 2>/dev/null || curl -s4 --connect-timeout 2 -m 4 https://api.ipify.org 2>/dev/null)
has_v6=$(curl -s6 --connect-timeout 2 -m 4 https://icanhazip.com 2>/dev/null || curl -s6 --connect-timeout 2 -m 4 https://api6.ipify.org 2>/dev/null)
has_v4=$(printf '%s' "$has_v4" | tr -d '[:space:]')
has_v6=$(printf '%s' "$has_v6" | tr -d '[:space:]')
# 清洗探测结果，避免非 IP 文本干扰单双栈判定
is_valid_ipv4 "$has_v4" || has_v4=""
is_valid_ipv6 "$has_v6" || has_v6=""
# 仅在确实无默认 IPv4 路由且双探测源均无 IPv4 时才判定为纯 IPv6 并配置 NAT64
if [[ -z "$has_v4" && -n "$has_v6" ]] && ! ip -4 route show default 2>/dev/null | grep -q .; then
echo
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
yellow "检测到 纯IPV6 VPS，添加NAT64（原配置已备份至 /etc/resolv.conf.sb.bak）"
[[ -f /etc/resolv.conf && ! -f /etc/resolv.conf.sb.bak ]] && cp -a /etc/resolv.conf /etc/resolv.conf.sb.bak 2>/dev/null || true
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1" > /etc/resolv.conf
ipv=prefer_ipv6
elif [[ -z "$has_v4" && -n "$has_v6" ]]; then
ipv=prefer_ipv6
else
ipv=prefer_ipv4
fi
if [ -n "$has_v6" ]; then
endip="2606:4700:d0::a29f:c001"
else
endip="162.159.192.1"
fi
}
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4orv6
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
v4orv6
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

close(){
systemctl stop firewalld.service >/dev/null 2>&1
systemctl disable firewalld.service >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -t mangle -F >/dev/null 2>&1
iptables -F >/dev/null 2>&1
iptables -X >/dev/null 2>&1
ip6tables -P INPUT ACCEPT >/dev/null 2>&1
ip6tables -P FORWARD ACCEPT >/dev/null 2>&1
ip6tables -P OUTPUT ACCEPT >/dev/null 2>&1
ip6tables -t mangle -F >/dev/null 2>&1
ip6tables -F >/dev/null 2>&1
ip6tables -X >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
sleep 1
green "执行开放端口，关闭防火墙完毕"
}

btpanel(){
[[ -d /www/server/panel ]]
}

fwtool(){
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
echo ufw
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
echo firewalld
else
echo iptables
fi
}

sbmainports(){
sbjq_read /etc/s-box/sb.json '.inbounds[] | select(.listen_port != null) | "\(.type) \(.listen_port)"' | while read -r type p; do
case $type in
hysteria2|tuic) echo "udp $p";;
vless|vmess|anytls) echo "tcp $p";;
esac
done
# 若启用了本地 IP 订阅服务，同步放行其监听端口
if [[ -s /etc/s-box/subport.log ]] && pgrep -f 'httpd.*websbox' >/dev/null 2>&1; then
local sp
sp=$(cat /etc/s-box/subport.log 2>/dev/null)
[[ $sp =~ ^[1-9][0-9]{0,4}$ && $sp -le 65535 ]] && echo "tcp $sp"
fi
}

sbfwopen(){
tool=$(fwtool)
: > /etc/s-box/fw_ports.log
while read -r proto p; do
case $tool in
ufw) ufw status 2>/dev/null | grep -qE "^$p/$proto[[:space:]]+ALLOW" && continue
ufw allow $p/$proto comment 'sb-auto' >/dev/null 2>&1;;
firewalld) firewall-cmd --permanent --query-port=$p/$proto >/dev/null 2>&1 && continue
firewall-cmd --permanent --add-port=$p/$proto >/dev/null 2>&1;;
*) for t in iptables ip6tables; do
$t -C INPUT -p $proto --dport $p -m comment --comment sb-auto -j ACCEPT >/dev/null 2>&1 || $t -I INPUT -p $proto --dport $p -m comment --comment sb-auto -j ACCEPT >/dev/null 2>&1
done;;
esac
echo "$tool $proto $p" >> /etc/s-box/fw_ports.log
done < <(sbmainports)
sbfwsave
[[ $tool = firewalld ]] && firewall-cmd --reload >/dev/null 2>&1 && bash /etc/s-box/sbfw.sh
blue "已通过 $tool 放行端口：$(sbmainports | awk '{print $2"/"$1}' | paste -sd' ')"
if btpanel; then
yellow "检测到宝塔面板：请在宝塔【安全】页面同样放行以上端口，以免宝塔同步防火墙规则时被覆盖"
fi
}

sbfwclose(){
[[ -f /etc/s-box/fw_ports.log ]] || return 0
reload=
while read -r tool proto p; do
case $tool in
ufw) ufw delete allow $p/$proto >/dev/null 2>&1;;
firewalld) firewall-cmd --permanent --remove-port=$p/$proto >/dev/null 2>&1; reload=1;;
*) for t in iptables ip6tables; do
while $t -D INPUT -p $proto --dport $p -m comment --comment sb-auto -j ACCEPT >/dev/null 2>&1; do :; done
done;;
esac
done < /etc/s-box/fw_ports.log
[[ -n $reload ]] && firewall-cmd --reload >/dev/null 2>&1 && [[ -f /etc/s-box/sbfw.sh ]] && bash /etc/s-box/sbfw.sh
rm -f /etc/s-box/fw_ports.log
}

sbfwre(){
if [[ "$(cat /etc/s-box/fwmode 2>/dev/null)" = "1" ]]; then
sbfwclose
sbfwopen
else
sbfwsave
fi
}

sbnatre(){
hp=$(sbjq_read /etc/s-box/sb.json '.inbounds[] | select(.type == "hysteria2") | .listen_port // empty')
tp=$(sbjq_read /etc/s-box/sb.json '.inbounds[] | select(.type == "tuic") | .listen_port // empty')
echo "$hp $tp" | xargs | tr ' ' '|'
}

# 添加 UDP 端口跳跃规则：优先使用 REDIRECT，失败时回退 DNAT，带 sb-auto 标记并去重，同时兼容 IPv4/IPv6
sbnatadd(){
local dport="$1" toport="$2" t
for t in iptables ip6tables; do
$t -t nat -C PREROUTING -p udp --dport "$dport" -m comment --comment sb-auto -j REDIRECT --to-ports "$toport" >/dev/null 2>&1 && continue
$t -t nat -C PREROUTING -p udp --dport "$dport" -m comment --comment sb-auto -j DNAT --to-destination ":$toport" >/dev/null 2>&1 && continue
$t -t nat -C PREROUTING -p udp --dport "$dport" -j REDIRECT --to-ports "$toport" >/dev/null 2>&1 && continue
$t -t nat -C PREROUTING -p udp --dport "$dport" -j DNAT --to-destination ":$toport" >/dev/null 2>&1 && continue
$t -t nat -A PREROUTING -p udp --dport "$dport" -m comment --comment sb-auto -j REDIRECT --to-ports "$toport" 2>/dev/null || \
$t -t nat -A PREROUTING -p udp --dport "$dport" -m comment --comment sb-auto -j DNAT --to-destination ":$toport" 2>/dev/null || \
$t -t nat -A PREROUTING -p udp --dport "$dport" -j REDIRECT --to-ports "$toport" 2>/dev/null || \
$t -t nat -A PREROUTING -p udp --dport "$dport" -j DNAT --to-destination ":$toport" 2>/dev/null
done
}

sbfwsave(){
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
service ip6tables save >/dev/null 2>&1
[[ -d /etc/s-box ]] || return 0
natre=$(sbnatre)
{
echo '#!/bin/bash'
for t in iptables ip6tables; do
if [[ -n $natre ]]; then
$t -t nat -S PREROUTING 2>/dev/null | grep -E -- "(-j REDIRECT --to-ports ($natre)|-j DNAT --to-destination (\[::\])?:($natre))$" | while read -r r; do
r=${r#-A }
echo "$t -t nat -C $r >/dev/null 2>&1 || $t -t nat -A $r >/dev/null 2>&1"
done
fi
$t -S INPUT 2>/dev/null | grep -E -- '--comment "?sb-auto"?' | while read -r r; do
r=${r#-A }
echo "$t -C $r >/dev/null 2>&1 || $t -I $r >/dev/null 2>&1"
done
done
} > /etc/s-box/sbfw.sh
chmod +x /etc/s-box/sbfw.sh
if command -v apk >/dev/null 2>&1 && [[ -d /etc/local.d ]]; then
printf '#!/bin/sh\nbash /etc/s-box/sbfw.sh\n' > /etc/local.d/sbfw.start
chmod +x /etc/local.d/sbfw.start
rc-update add local default >/dev/null 2>&1
fi
}

sbnatports(){
{
iptables -t nat -S PREROUTING 2>/dev/null
ip6tables -t nat -S PREROUTING 2>/dev/null
} | grep -E -- "-p udp .*(-j REDIRECT --to-ports $1|-j DNAT --to-destination (\[::\])?:$1)$" | grep -oE -- '--dport [0-9:]+' | awk '{print $2}' | awk '!seen[$0]++' | paste -sd,
}

sbnatconflict(){
local nproto np nr nt ns ne
while read -r nproto np; do
if [[ $nproto = udp && $np != "$3" && $np -ge $1 && $np -le $2 ]]; then
echo "端口 $np 是其他协议的主端口"
return 0
fi
done < <(sbmainports)
while read -r nr nt; do
[[ $nr =~ ^[0-9]+(:[0-9]+)?$ && $nt =~ ^[0-9]+$ ]] || continue
ns=${nr%%:*}
ne=${nr##*:}
if [[ $nt != "$3" && $ns -le $2 && $ne -ge $1 ]]; then
echo "与已有的转发端口 $nr (转发到 $nt) 重叠"
return 0
fi
done < <({
iptables -t nat -S PREROUTING 2>/dev/null
ip6tables -t nat -S PREROUTING 2>/dev/null
} | grep -E -- '-p udp .*--dport [0-9:]+ .*(-j REDIRECT --to-ports [0-9]+|-j DNAT --to-destination (\[::\])?:[0-9]+)$' | sed -E 's/.*--dport ([0-9:]+) .*(--to-ports |--to-destination (\[::\])?:)([0-9]+)$/\1 \4/' | sort -u)
return 1
}

sbnatclr(){
local t r
for t in iptables ip6tables; do
$t -t nat -S PREROUTING 2>/dev/null | grep -E -- "-p udp .*--dport $1( .*)? -j (REDIRECT|DNAT)" | while read -r r; do
eval "$t -t nat -D ${r#-A }" >/dev/null 2>&1
done
done
}

# 清理指向本机未监听 UDP 端口的失效（孤儿）端口跳跃规则，避免劫持新端口
sbnatprune(){
local t r nt live_udp cur_ports cleared=0
live_udp=$(ss -lun 2>/dev/null | awk 'NR>1{print $4}' | sed 's/.*://' | grep -E '^[0-9]+$' | sort -u)
cur_ports=$(sbnatre 2>/dev/null)
for t in iptables ip6tables; do
while read -r r; do
[[ -n $r ]] || continue
nt=$(echo "$r" | sed -E 's/.*(--to-ports |--to-destination (\[::\])?:)([0-9]+)$/\3/')
[[ $nt =~ ^[0-9]+$ ]] || continue
echo "$live_udp" | grep -qx "$nt" && continue
if [[ -n $cur_ports ]] && echo "$cur_ports" | tr '|' '\n' | grep -qx "$nt"; then
continue
fi
eval "$t -t nat -D ${r#-A }" >/dev/null 2>&1 && cleared=$((cleared + 1))
done < <($t -t nat -S PREROUTING 2>/dev/null | grep -E -- '-p udp .*--dport [0-9:]+ .*(-j REDIRECT --to-ports [0-9]+|-j DNAT --to-destination (\[::\])?:[0-9]+)$')
done
if [[ $cleared -gt 0 ]]; then
yellow "已自动清理 $cleared 条失效的 UDP NAT 残留转发规则（目标端口未监听）"
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
service ip6tables save >/dev/null 2>&1
fi
}

sbnatdel(){
local t r
natre=$(sbnatre)
for t in iptables ip6tables; do
if [[ -n $natre ]]; then
$t -t nat -S PREROUTING 2>/dev/null | grep -E -- "(-j REDIRECT --to-ports ($natre)|-j DNAT --to-destination (\[::\])?:($natre))$" | while read -r r; do
eval "$t -t nat -D ${r#-A }" >/dev/null 2>&1
done
fi
$t -t nat -S PREROUTING 2>/dev/null | grep -E -- '--comment "?sb-auto"?' | while read -r r; do
eval "$t -t nat -D ${r#-A }" >/dev/null 2>&1
done
done
sbnatclr 50000:60000
sbnatclr 40000:49999
netfilter-persistent save >/dev/null 2>&1
service iptables save >/dev/null 2>&1
service ip6tables save >/dev/null 2>&1
}

openyn(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
readp "防火墙处理方式？\n1、只放行脚本所需端口，保留现有防火墙 (回车默认，推荐)\n2、跳过，自行处理\n3、完全关闭防火墙并清空iptables规则 (会破坏宝塔等面板的防火墙)\n请选择【1-3】：" action
if [[ -z $action ]] || [[ "$action" = "1" ]]; then
fwact=1
elif [[ "$action" = "2" ]]; then
fwact=2
elif [[ "$action" = "3" ]]; then
if btpanel; then
red "检测到宝塔面板，完全关闭防火墙会清空宝塔的防火墙规则！"
readp "确认仍要完全关闭？输入 yes 确认，其它任意键返回：" confirm
[[ "$confirm" != "yes" ]] && openyn && return
fi
fwact=3
close
else
red "输入错误,请重新选择" && openyn && return
fi
echo "$fwact" > /etc/s-box/fwmode
}

inssb(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "使用哪个内核版本？"
yellow "1：使用目前最新正式版内核 (回车默认)"
yellow "2：使用之前1.10.7正式版内核 (支持geosite分流、IP优选级切换，无Anytls协议)"
readp "请选择【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
sbcore=$(curl -Ls --connect-timeout 5 -m 15 https://github.com/SagerNet/sing-box/releases/latest | grep -oE 'tag/v[0-9.]+' | head -n 1 | sed 's|tag/v||')
if [[ -z "$sbcore" ]]; then
sbcore=$(curl -Ls --connect-timeout 5 -m 10 https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box | grep -Eo '"[0-9.]+"[,\]]' | head -n 1 | tr -d '",]')
fi
else
sbcore='1.10.7'
fi
if [[ -z "$sbcore" ]]; then
red "获取 Sing-box 最新版本号失败，请检测VPS网络是否可以访问 Github" && exit 1
fi
sbname="sing-box-$sbcore-linux-$cpu"
rm -rf /etc/s-box/sing-box.tar.gz "/etc/s-box/$sbname"
if ! curl -fL -o /etc/s-box/sing-box.tar.gz -# --retry 2 --connect-timeout 10 https://github.com/SagerNet/sing-box/releases/download/v$sbcore/$sbname.tar.gz; then
rm -f /etc/s-box/sing-box.tar.gz
red "下载 Sing-box 内核失败，请再运行安装一次，并检测VPS的网络是否可以访问Github" && exit 1
fi
if tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box && [[ -f "/etc/s-box/$sbname/sing-box" ]]; then
mv -f "/etc/s-box/$sbname/sing-box" /etc/s-box/sing-box
rm -rf /etc/s-box/sing-box.tar.gz "/etc/s-box/$sbname"
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
blue "成功安装 Sing-box 内核版本：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')"
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
else
rm -rf /etc/s-box/sing-box.tar.gz "/etc/s-box/$sbname"
red "下载 Sing-box 内核不完整，安装失败，请再运行安装一次" && exit 1
fi
}

inscertificate(){
ymzs(){
ym_vl_re=apple.com
echo
blue "Vless-reality的SNI域名默认为 apple.com"
tlsyn=true
ym_vm_ws=$(cat /root/ygkkkca/ca.log 2>/dev/null)
certificatec_vmess_ws='/root/ygkkkca/cert.crt'
certificatep_vmess_ws='/root/ygkkkca/private.key'
certificatec_hy2='/root/ygkkkca/cert.crt'
certificatep_hy2='/root/ygkkkca/private.key'
certificatec_tuic='/root/ygkkkca/cert.crt'
certificatep_tuic='/root/ygkkkca/private.key'
certificatec_an='/root/ygkkkca/cert.crt'
certificatep_an='/root/ygkkkca/private.key'
}

zqzs(){
ym_vl_re=apple.com
echo
blue "Vless-reality的SNI域名默认为 apple.com"
tlsyn=false
ym_vm_ws=www.bing.com
certificatec_vmess_ws='/etc/s-box/cert.pem'
certificatep_vmess_ws='/etc/s-box/private.key'
certificatec_hy2='/etc/s-box/cert.pem'
certificatep_hy2='/etc/s-box/private.key'
certificatec_tuic='/etc/s-box/cert.pem'
certificatep_tuic='/etc/s-box/private.key'
certificatec_an='/etc/s-box/cert.pem'
certificatep_an='/etc/s-box/private.key'
}

red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "二、生成并设置相关证书"
echo
blue "自动生成bing自签证书中……" && sleep 2
openssl ecparam -genkey -name prime256v1 -out /etc/s-box/private.key
openssl req -new -x509 -days 36500 -key /etc/s-box/private.key -out /etc/s-box/cert.pem -subj "/CN=www.bing.com"
echo
if [[ -f /etc/s-box/cert.pem ]]; then
blue "生成bing自签证书成功"
else
red "生成bing自签证书失败" && exit
fi
echo
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key && -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]]; then
yellow "经检测，之前已使用Acme-yg脚本申请过Acme域名IP证书：$(cat /root/ygkkkca/ca.log) "
green "是否使用 $(cat /root/ygkkkca/ca.log) 域名IP证书？"
yellow "1：否！使用自签的证书 (回车默认)"
yellow "2：是！使用 $(cat /root/ygkkkca/ca.log) 域名IP证书"
readp "请选择【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
ymzs
fi
else
green "是否申请一个Acme域名IP证书？"
yellow "1：否！继续使用自签的证书 (回车默认)"
yellow "2：是！使用Acme-yg脚本申请Acme证书 (支持80端口域名IP证书模式与Dns API域名模式)"
btpanel && yellow "提示：检测到宝塔面板，80端口通常被宝塔Nginx占用，建议选择Dns API模式，或继续使用自签证书"
readp "请选择【1-2】：" menu
if [ -z "$menu" ] || [ "$menu" = "1" ] ; then
zqzs
else
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
if [[ ! -s /root/ygkkkca/cert.crt || ! -s /root/ygkkkca/private.key ]]; then
red "Acme证书申请失败，继续使用自签证书" 
zqzs
else
ymzs
fi
fi
fi
}

portused(){
[[ -n $(ss -tunlp 2>/dev/null | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || -n $(ss -tunlp 2>/dev/null | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") || " ${_sb_chosen_ports} " == *" $port "* ]]
}

portnat(){
[[ $udpchk = 1 ]] && natmsg=$(sbnatconflict $port $port)
}

chooseport(){
while :; do
if [[ -z $port ]]; then
port=$(shuf -i 10000-65535 -n 1)
while portused || portnat; do port=$(shuf -i 10000-65535 -n 1); done
fi
if ! [[ $port =~ ^[1-9][0-9]{0,4}$ && $port -le 65535 ]]; then
yellow "\n端口必须是 1-65535 之间的数字，请重新输入端口" && readp "自定义端口:" port
elif portused; then
yellow "\n端口被占用或与其他协议重复，请重新输入端口" && readp "自定义端口:" port
elif portnat; then
yellow "\n端口 $port 不可用：$natmsg" && readp "自定义端口:" port
else
break
fi
done
blue "确认的端口：$port" && sleep 1
}

chooseudpport(){
udpchk=1
chooseport
udpchk=
}

vlport(){
readp "\n设置Vless-reality端口 (回车跳过为10000-65535之间的随机端口)：" port
chooseport
port_vl_re=$port
}
vmport(){
readp "\n设置Vmess-ws端口 (回车跳过为10000-65535之间的随机端口)：" port
chooseport
port_vm_ws=$port
}
hy2port(){
readp "\n设置Hysteria2主端口 (回车跳过为10000-65535之间的随机端口)：" port
chooseudpport
port_hy2=$port
}
tu5port(){
readp "\n设置Tuic5主端口 (回车跳过为10000-65535之间的随机端口)：" port
chooseudpport
port_tu=$port
}
anport(){
readp "\n设置Anytls主端口，最新内核时可用 (回车跳过为10000-65535之间的随机端口)：" port
chooseport
port_an=$port
}

insport(){
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "三、设置各个协议端口"
yellow "1：自动生成每个协议的随机端口 (10000-65535范围内)，回车默认。请确保VPS后台已开放所有端口"
yellow "2：自定义每个协议端口。请确保VPS后台已开放指定的端口"
readp "请输入【1-2】：" port
if [ -z "$port" ] || [ "$port" = "1" ] ; then
ports=()
for i in {1..5}; do
while true; do
port=$(shuf -i 10000-65535 -n 1)
if ! [[ " ${ports[@]} " =~ " $port " ]] && \
[[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && \
[[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
ports+=($port)
break
fi
done
done
port_vm_ws=${ports[0]}
port_vl_re=${ports[1]}
port_hy2=${ports[2]}
port_tu=${ports[3]}
port_an=${ports[4]}
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
until [[ -z $(ss -tunlp | grep -w tcp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_vm_ws") ]]
do
if [[ $tlsyn == "true" ]]; then
numbers=("2053" "2083" "2087" "2096" "8443")
else
numbers=("8080" "8880" "2052" "2082" "2086" "2095")
fi
port_vm_ws=${numbers[$RANDOM % ${#numbers[@]}]}
done
echo
blue "根据Vmess-ws协议是否启用TLS，随机指定支持CDN优选IP的标准端口：$port_vm_ws"
else
_sb_chosen_ports=""
vlport && _sb_chosen_ports="$_sb_chosen_ports $port_vl_re"
vmport && _sb_chosen_ports="$_sb_chosen_ports $port_vm_ws"
hy2port && _sb_chosen_ports="$_sb_chosen_ports $port_hy2"
tu5port && _sb_chosen_ports="$_sb_chosen_ports $port_tu"
if [[ "$sbnh" != "1.10" ]]; then
anport
else
# 1.10 内核也给 sb11.json 预留一个合法的随机 Anytls 端口，避免升级内核切换配置时报 JSON 语法错误
while :; do
port_an=$(shuf -i 10000-65535 -n 1)
port=$port_an
! portused && break
done
fi
_sb_chosen_ports=""
fi
echo
blue "各协议端口确认如下"
blue "Vless-reality端口：$port_vl_re"
blue "Vmess-ws端口：$port_vm_ws"
blue "Hysteria-2端口：$port_hy2"
blue "Tuic-v5端口：$port_tu"
if [[ "$sbnh" != "1.10" ]]; then
blue "Anytls端口：$port_an"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "四、自动生成各个协议统一的uuid (密码)"
uuid=$(/etc/s-box/sing-box generate uuid)
blue "已确认uuid (密码)：${uuid}"
hy2_obfs=$(openssl rand -hex 16)
blue "已确认Hysteria2的Salamander混淆密码：${hy2_obfs}"
blue "已确认Vmess的path路径：${uuid}-vm"
}

inssbjsonser(){
cat > /etc/s-box/sb10.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "sniff": true,
      "sniff_override_destination": true,
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",
        "sniff": true,
        "sniff_override_destination": true,
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ], "obfs": {"type": "salamander", "password": "${hy2_obfs}"},
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",
            "sniff": true,
            "sniff_override_destination": true,
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        }
],
"outbounds": [
{
"type":"direct",
"tag":"direct",
"domain_strategy": "$ipv"
},
{
"type":"direct",
"tag": "vps-outbound-v4", 
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag": "vps-outbound-v6",
"domain_strategy":"prefer_ipv6"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
},
{
"type":"direct",
"tag":"socks-IPv4-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"socks-IPv6-out",
"detour":"socks-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"direct",
"tag":"warp-IPv4-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv4"
},
{
"type":"direct",
"tag":"warp-IPv6-out",
"detour":"wireguard-out",
"domain_strategy":"prefer_ipv6"
},
{
"type":"wireguard",
"tag":"wireguard-out",
"server":"$endip",
"server_port":2408,
"local_address":[
"172.16.0.2/32",
"${warp_v6}/128"
],
"private_key":"$pvk",
"peer_public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"reserved":$res
},
{
"type": "block",
"tag": "block"
}
],
"route":{
"rules":[
{
"protocol": [
"quic",
"stun"
],
"outbound": "block"
},
{
"outbound":"warp-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"warp-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv4-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"socks-IPv6-out",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v4",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound":"vps-outbound-v6",
"domain_suffix": [
"yg_kkk"
]
,"geosite": [
"yg_kkk"
]
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF

cat > /etc/s-box/sb11.json <<EOF
{
"log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",

      
      "tag": "vless-sb",
      "listen": "::",
      "listen_port": ${port_vl_re},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${ym_vl_re}",
          "reality": {
          "enabled": true,
          "handshake": {
            "server": "${ym_vl_re}",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    },
{
        "type": "vmess",

 
        "tag": "vmess-sb",
        "listen": "::",
        "listen_port": ${port_vm_ws},
        "users": [
            {
                "uuid": "${uuid}",
                "alterId": 0
            }
        ],
        "transport": {
            "type": "ws",
            "path": "${uuid}-vm",
            "max_early_data":2048,
            "early_data_header_name": "Sec-WebSocket-Protocol"    
        },
        "tls":{
                "enabled": ${tlsyn},
                "server_name": "${ym_vm_ws}",
                "certificate_path": "$certificatec_vmess_ws",
                "key_path": "$certificatep_vmess_ws"
            }
    }, 
    {
        "type": "hysteria2",

 
        "tag": "hy2-sb",
        "listen": "::",
        "listen_port": ${port_hy2},
        "users": [
            {
                "password": "${uuid}"
            }
        ], "obfs": {"type": "salamander", "password": "${hy2_obfs}"},
        "ignore_client_bandwidth":false,
        "tls": {
            "enabled": true,
            "alpn": [
                "h3"
            ],
            "certificate_path": "$certificatec_hy2",
            "key_path": "$certificatep_hy2"
        }
    },
        {
            "type":"tuic",

     
            "tag": "tuic5-sb",
            "listen": "::",
            "listen_port": ${port_tu},
            "users": [
                {
                    "uuid": "${uuid}",
                    "password": "${uuid}"
                }
            ],
            "congestion_control": "bbr",
            "tls":{
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "$certificatec_tuic",
                "key_path": "$certificatep_tuic"
            }
        },
        {
            "type":"anytls",
            "tag":"anytls-sb",
            "listen":"::",
            "listen_port":${port_an},
            "users":[
                {
                  "password":"${uuid}"
                }
            ],
            "padding_scheme":[],
            "tls":{
                "enabled": true,
                "certificate_path": "$certificatec_an",
                "key_path": "$certificatep_an"
            }
        }
],
"endpoints":[
{
"type":"wireguard",
"tag":"warp-out",
"address":[
"172.16.0.2/32",
"${warp_v6}/128"
],
"private_key":"$pvk",
"peers": [
{
"address": "$endip",
"port":2408,
"public_key":"bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
"allowed_ips": [
"0.0.0.0/0",
"::/0"
],
"reserved":$res
}
]
}
],









"outbounds": [
{
"type":"direct",
"tag":"direct"
},
{
"type": "socks",
"tag": "socks-out",
"server": "127.0.0.1",
"server_port": 40000,
"version": "5"
}
],
"route":{
"rules":[
{
 "action": "sniff"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv4"
},
{
"action": "resolve",
"domain_suffix":[
"yg_kkk"
],
"strategy": "prefer_ipv6"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"socks-out"
},
{
"domain_suffix":[
"yg_kkk"
],
"outbound":"warp-out"
},
{
"outbound": "direct",
"network": "udp,tcp"
}
]
}
}
EOF
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
}

sbservice(){
if command -v apk >/dev/null 2>&1; then
echo '#!/sbin/openrc-run
description="sing-box service"
command="/etc/s-box/sing-box"
command_args="run -c /etc/s-box/sb.json"
command_background=true
pidfile="/var/run/sing-box.pid"' > /etc/init.d/sing-box
chmod +x /etc/init.d/sing-box
rc-update add sing-box default
rc-service sing-box start
else
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
After=network.target nss-lookup.target
[Service]
User=root
WorkingDirectory=/root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl start sing-box
systemctl restart sing-box
fi
}

ipuuid(){
if command -v apk >/dev/null 2>&1; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl is-active sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
v4v6 force
# 若 IPv4 与 IPv6 均未获取到有效地址，保留旧文件不覆盖
if [[ -z "$v4" && -z "$v6" ]]; then
red "获取本地 IPv4/IPv6 地址失败，已保留原有配置不覆盖"
return 1
fi
# 分别记录纯 IPv4 与纯 IPv6 地址（不存在则清空）
if [[ -n "$v4" ]]; then
echo "$v4" > /etc/s-box/server_ipv4.log
else
: > /etc/s-box/server_ipv4.log
fi
if [[ -n "$v6" ]]; then
echo "$v6" > /etc/s-box/server_ipv6.log
else
: > /etc/s-box/server_ipv6.log
fi
# 同时维护向后兼容的 server_ip.log 与 server_ipcl.log（优先 IPv4，纯 IPv6 时带/不带方括号）
if [[ -n "$v4" ]]; then
server_ip="$v4"
server_ipcl="$v4"
else
server_ip="[$v6]"
server_ipcl="$v6"
fi
echo "$server_ip" > /etc/s-box/server_ip.log
echo "$server_ipcl" > /etc/s-box/server_ipcl.log
if [[ -n "$v4" && -n "$v6" ]]; then
green "已刷新双栈本地 IP：IPv4=${v4}，IPv6=${v6}（将同时输出 IPv4 和 IPv6 配置）"
elif [[ -n "$v4" ]]; then
green "已刷新本地 IPv4：${v4}"
else
green "已刷新本地 IPv6：${v6}"
fi
else
red "Sing-box服务未运行" && exit
fi
}

wgcfgo(){
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
ipuuid
else
systemctl stop wg-quick@wgcf >/dev/null 2>&1
kill -15 $(pgrep warp-go) >/dev/null 2>&1 && sleep 2
ipuuid
systemctl start wg-quick@wgcf >/dev/null 2>&1
systemctl restart warp-go >/dev/null 2>&1
systemctl enable warp-go >/dev/null 2>&1
systemctl start warp-go >/dev/null 2>&1
fi
}

result_vl_vm_hy_tu(){
# 仅在 ca.log 缺失/为空且 acme.sh 可正常返回有效域名时才补写，避免覆盖或清空已有 ca.log
if [[ -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key && ! -s /root/ygkkkca/ca.log && -f ~/.acme.sh/acme.sh ]]; then
ym=$(bash ~/.acme.sh/acme.sh --list 2>/dev/null | awk 'NR>1 && $1!="" {d=$1} END{print d}')
[[ -n "$ym" ]] && echo "$ym" > /root/ygkkkca/ca.log
fi
rm -rf /etc/s-box/vm_ws_argo.txt /etc/s-box/vm_ws.txt /etc/s-box/vm_ws_tls.txt
# 读取并校验双栈本地 IP，兼容老环境从 server_ipcl.log 回退
server_ipv4=$(tr -d '[:space:]' < /etc/s-box/server_ipv4.log 2>/dev/null)
server_ipv6=$(tr -d '[:space:]' < /etc/s-box/server_ipv6.log 2>/dev/null)
is_valid_ipv4 "$server_ipv4" || server_ipv4=""
is_valid_ipv6 "$server_ipv6" || server_ipv6=""
if [[ ! -f /etc/s-box/server_ipv4.log && ! -f /etc/s-box/server_ipv6.log ]]; then
local _old_ip
_old_ip=$(tr -d '[:space:]' < /etc/s-box/server_ipcl.log 2>/dev/null)
if is_valid_ipv4 "$_old_ip"; then
server_ipv4="$_old_ip"
elif is_valid_ipv6 "$_old_ip"; then
server_ipv6="$_old_ip"
fi
fi
# 构建直连 IP 列表与标签后缀（双栈区分 -v4/-v6，单栈后缀为空）
server_ips_list=()
server_ip_tags=()
if [[ -n "$server_ipv4" && -n "$server_ipv6" ]]; then
server_ips_list=("$server_ipv4" "$server_ipv6")
server_ip_tags=("-v4" "-v6")
elif [[ -n "$server_ipv4" ]]; then
server_ips_list=("$server_ipv4")
server_ip_tags=("")
elif [[ -n "$server_ipv6" ]]; then
server_ips_list=("$server_ipv6")
server_ip_tags=("")
fi
server_ip=$(cat /etc/s-box/server_ip.log 2>/dev/null)
server_ipcl=$(cat /etc/s-box/server_ipcl.log 2>/dev/null)
if [[ -z "$server_ipcl" && ${#server_ips_list[@]} -gt 0 ]]; then
server_ipcl="${server_ips_list[0]}"
[[ "$server_ipcl" == *:* ]] && server_ip="[$server_ipcl]" || server_ip="$server_ipcl"
fi
uuid=$(sbjq_read /etc/s-box/sb.json '.inbounds[0].users[0].uuid')
vl_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[0].listen_port')
vl_name=$(sbjq_read /etc/s-box/sb.json '.inbounds[0].tls.server_name')
public_key=$(cat /etc/s-box/public.key 2>/dev/null)
short_id=$(sbjq_read /etc/s-box/sb.json '.inbounds[0].tls.reality.short_id[0]')
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
argogd=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
ws_path=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].transport.path')
vm_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].listen_port')
tls=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].tls.enabled')
vm_name=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].tls.server_name')
vm_is_direct_ip=0
if [[ "$tls" = "false" ]]; then
if [[ -s /etc/s-box/cfymjx.txt ]]; then
vm_name=$(cat /etc/s-box/cfymjx.txt 2>/dev/null)
fi
vmadd_local=$server_ipcl
vmadd_are_local=$server_ipcl
vm_is_direct_ip=1
else
vmadd_local=$vm_name
vmadd_are_local=$vm_name
fi
if [[ -s /etc/s-box/cfvmadd_local.txt ]]; then
# 若用户输入的优选 IPv6 带方括号，自动去除方括号以保证 JSON/YAML 合法
vmadd_local=$(tr -d '[:space:]' < /etc/s-box/cfvmadd_local.txt 2>/dev/null | sed 's/^\[//;s/\]$//')
vmadd_are_local="$vmadd_local"
vm_is_direct_ip=0
fi
if [[ -s /etc/s-box/cfvmadd_argo.txt ]]; then
vmadd_argo=$(tr -d '[:space:]' < /etc/s-box/cfvmadd_argo.txt 2>/dev/null | sed 's/^\[//;s/\]$//')
else
vmadd_argo=cloudflare-ech.com
fi
hy2_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[2].listen_port')
hy2_obfs=$(sbjq_read /etc/s-box/sb.json '.inbounds[2].obfs.password // empty')
if [[ -n $hy2_obfs ]]; then
hyobfs="&obfs=salamander&obfs-password=$hy2_obfs"
else
hyobfs=
fi
hy2_ports=$(sbnatports "$hy2_port")
if [[ -n $hy2_ports ]]; then
cmhy2pt=$(echo "$hy2_ports" | tr ':' '-')
hyps="&mport=$cmhy2pt"
sbhy2pt=$(echo "$hy2_ports" | tr ',' '\n' | sed -E 's/^([0-9]+)$/\1:\1/; s/.*/"&"/' | paste -sd,)
else
hyps=
cmhy2pt=
sbhy2pt=
fi
hy2_hop=15
hy2_up=50
hy2_down=200
if [[ -s /etc/s-box/hy2_bw.txt ]]; then
hy2_up=$(awk '{print $1}' /etc/s-box/hy2_bw.txt)
hy2_down=$(awk '{print $2}' /etc/s-box/hy2_bw.txt)
fi
ym=$(cat /root/ygkkkca/ca.log 2>/dev/null)
hy2_sniname=$(sbjq_read /etc/s-box/sb.json '.inbounds[2].tls.key_path')
SHA256=""
hypin=""
if [[ "$hy2_sniname" = '/etc/s-box/private.key' ]]; then
SHA256=$(openssl x509 -in /etc/s-box/cert.pem -outform DER 2>/dev/null | sha256sum | awk '{print $1}')
echo "$SHA256" > /etc/s-box/SHA256.txt
[[ -n "$SHA256" ]] && hypin="&pinSHA256=$SHA256"
hy2_name=www.bing.com
sb_hy2_ip=$server_ip
cl_hy2_ip=$server_ipcl
ins_hy2=1
hy2_ins=true
hy2_is_direct_ip=1
else
hy2_name=$ym
sb_hy2_ip=$ym
cl_hy2_ip=$ym
ins_hy2=0
hy2_ins=false
hy2_is_direct_ip=0
fi
tu5_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[3].listen_port')
tu5_sniname=$(sbjq_read /etc/s-box/sb.json '.inbounds[3].tls.key_path')
if [[ "$tu5_sniname" = '/etc/s-box/private.key' ]]; then
tu5_name=www.bing.com
sb_tu5_ip=$server_ip
cl_tu5_ip=$server_ipcl
ins=1
tu5_ins=true
tu5_is_direct_ip=1
else
tu5_name=$ym
sb_tu5_ip=$ym
cl_tu5_ip=$ym
ins=0
tu5_ins=false
tu5_is_direct_ip=0
fi
an_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[4].listen_port // empty')
an_sniname=$(sbjq_read /etc/s-box/sb.json '.inbounds[4].tls.key_path // empty')
if [[ "$an_sniname" = '/etc/s-box/private.key' ]]; then
an_name=www.bing.com
sb_an_ip=$server_ip
cl_an_ip=$server_ipcl
ins_an=1
an_ins=true
an_is_direct_ip=1
else
an_name=$ym
sb_an_ip=$ym
cl_an_ip=$ym
ins_an=0
an_ins=false
an_is_direct_ip=0
fi
}

resvless(){
local i ip tag host_uri vl_link
: > /etc/s-box/vl_reality.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vless-reality-vision 】节点信息如下：" && sleep 2
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
host_uri=$(fmt_host_port "$ip" "$vl_port")
vl_link="vless://$uuid@$host_uri?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vl_name&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#vl-reality-$hostname$tag"
echo "$vl_link" >> /etc/s-box/vl_reality.txt
echo
echo "分享链接${tag}【v2ran(切换singbox内核)、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vl_link${plain}"
echo
echo "二维码${tag}【v2ran(切换singbox内核)、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$vl_link"
done
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resvmess(){
local i ip tag vm_link
if [[ "$tls" = "false" ]]; then
if ps -ef 2>/dev/null | grep "[l]ocalhost:${vm_port}" >/dev/null 2>&1; then
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】临时节点信息如下(可选择3-8-3，自定义CDN优选地址)：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
vm_link="vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argo'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argo'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
echo -e "${yellow}$vm_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo "$vm_link" > /etc/s-box/vm_ws_argols.txt
qrencode -o - -t ANSIUTF8 "$vm_link"
fi
if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
argogd=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws(tls)+Argo 】固定节点信息如下 (可选择3-8-3，自定义CDN优选地址)：" && sleep 2
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
vm_link="vmess://$(echo '{"add":"'$vmadd_argo'","aid":"0","host":"'$argogd'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"443","ps":"'vm-argo-$hostname'","tls":"tls","sni":"'$argogd'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
echo -e "${yellow}$vm_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo "$vm_link" > /etc/s-box/vm_ws_argogd.txt
qrencode -o - -t ANSIUTF8 "$vm_link"
fi
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
: > /etc/s-box/vm_ws.txt
if [[ "$vm_is_direct_ip" = "1" ]]; then
# 直连 VPS IP 时同时输出双栈节点，JSON 中 add 字段严格使用不带方括号的纯 IP
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
vm_link="vmess://$(echo '{"add":"'$ip'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname$tag'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
echo "$vm_link" >> /etc/s-box/vm_ws.txt
echo
echo "分享链接${tag}【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vm_link${plain}"
echo
echo "二维码${tag}【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$vm_link"
done
else
vm_link="vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-$hostname'","tls":"","type":"none","v":"2"}' | base64 -w 0)"
echo "$vm_link" > /etc/s-box/vm_ws.txt
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vm_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$vm_link"
fi
else
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 vmess-ws-tls 】节点信息如下 (建议选择3-8-1，设置为CDN优选节点)：" && sleep 2
vm_link="vmess://$(echo '{"add":"'$vmadd_are_local'","aid":"0","host":"'$vm_name'","id":"'$uuid'","net":"ws","path":"'$ws_path'","port":"'$vm_port'","ps":"'vm-ws-tls-$hostname'","tls":"tls","sni":"'$vm_name'","fp":"chrome","type":"none","v":"2"}' | base64 -w 0)"
echo "$vm_link" > /etc/s-box/vm_ws_tls.txt
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$vm_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$vm_link"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

reshy2(){
local i ip tag host_uri hy2_link
: > /etc/s-box/hy2.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
hyext=
[[ -n $hyps ]] && hyext="&hop-interval=$hy2_hop"
[[ -n $hy2_up && -n $hy2_down ]] && hyext="$hyext&upmbps=$hy2_up&downmbps=$hy2_down"
red "🚀【 Hysteria-2 】节点信息如下：" && sleep 2
# 仅自签证书附带 pinSHA256，且自签直连 VPS IP 时同时输出双栈节点
if [[ "$hy2_is_direct_ip" = "1" ]]; then
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
host_uri=$(fmt_host_port "$ip" "$hy2_port")
hy2_link="hysteria2://$uuid@$host_uri?security=tls&alpn=h3&insecure=0&allowInsecure=0$hyps$hyext$hyobfs&sni=$hy2_name$hypin#hy2-$hostname$tag"
echo "$hy2_link" >> /etc/s-box/hy2.txt
echo
echo "分享链接${tag}【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$hy2_link${plain}"
echo
echo "二维码${tag}【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$hy2_link"
done
else
hy2_link="hysteria2://$uuid@$sb_hy2_ip:$hy2_port?security=tls&alpn=h3&insecure=0&allowInsecure=0$hyps$hyext$hyobfs&sni=$hy2_name$hypin#hy2-$hostname"
echo "$hy2_link" > /etc/s-box/hy2.txt
echo
echo "分享链接【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$hy2_link${plain}"
echo
echo "二维码【v2rayn、v2rayng、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$hy2_link"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

restu5(){
local i ip tag host_uri tuic5_link
: > /etc/s-box/tuic5.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Tuic-v5 】节点信息如下：" && sleep 2
if [[ "$tu5_is_direct_ip" = "1" ]]; then
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
host_uri=$(fmt_host_port "$ip" "$tu5_port")
tuic5_link="tuic://$uuid:$uuid@$host_uri?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&insecure=$ins&allowInsecure=$ins&allow_insecure=$ins#tu5-$hostname$tag"
echo "$tuic5_link" >> /etc/s-box/tuic5.txt
echo
echo "分享链接${tag}【v2rayn、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$tuic5_link${plain}"
echo
echo "二维码${tag}【v2rayn、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$tuic5_link"
done
else
tuic5_link="tuic://$uuid:$uuid@$sb_tu5_ip:$tu5_port?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=$tu5_name&insecure=$ins&allowInsecure=$ins&allow_insecure=$ins#tu5-$hostname"
echo "$tuic5_link" > /etc/s-box/tuic5.txt
echo
echo "分享链接【v2rayn、nekobox、小火箭shadowrocket】"
echo -e "${yellow}$tuic5_link${plain}"
echo
echo "二维码【v2rayn、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$tuic5_link"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

resan(){
local i ip tag host_uri an_link
: > /etc/s-box/an.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 Anytls】节点信息如下：" && sleep 2
if [[ "$an_is_direct_ip" = "1" ]]; then
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
host_uri=$(fmt_host_port "$ip" "$an_port")
an_link="anytls://$uuid@$host_uri?&sni=$an_name&allowInsecure=$ins_an&insecure=$ins_an#anytls-$hostname$tag"
echo "$an_link" >> /etc/s-box/an.txt
echo
echo "分享链接${tag}【v2rayn、小火箭shadowrocket】"
echo -e "${yellow}$an_link${plain}"
echo
echo "二维码${tag}【v2rayn、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$an_link"
done
else
an_link="anytls://$uuid@$sb_an_ip:$an_port?&sni=$an_name&allowInsecure=$ins_an&insecure=$ins_an#anytls-$hostname"
echo "$an_link" > /etc/s-box/an.txt
echo
echo "分享链接【v2rayn、小火箭shadowrocket】"
echo -e "${yellow}$an_link${plain}"
echo
echo "二维码【v2rayn、nekobox、小火箭shadowrocket】"
qrencode -o - -t ANSIUTF8 "$an_link"
fi
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

sb_client(){

sbhy2ports(){
# sing-box 中 server_port 与 server_ports 互斥，仅输出其中之一
if [[ -n $hy2_ports ]]; then
    cat <<EOF
        "server_ports": [ $sbhy2pt ],
EOF
    if [[ "$sbnh" != "1.10" ]]; then
    cat <<EOF
        "hop_interval": "${hy2_hop}s",
EOF
    fi
else
    cat <<EOF
        "server_port": $hy2_port,
EOF
fi
}

sbvmess_tls(){
if [[ "$1" = "true" ]]; then
    cat <<EOF
            "tls": {
                "enabled": true,
                "server_name": "$2",
                "insecure": false,
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                }
            },
EOF
else
    cat <<EOF
            "tls": {
                "enabled": false
            },
EOF
fi
}

sbhy2obfs(){
if [[ -n $hy2_obfs ]]; then
    cat <<EOF
        "obfs": {
            "type": "salamander",
            "password": "$hy2_obfs"
        },
EOF
fi
}

sbhy2bw(){
if [[ -n $hy2_up && -n $hy2_down ]]; then
    cat <<EOF
        "up_mbps": $hy2_up,
        "down_mbps": $hy2_down,
EOF
fi
}

clhy2obfs(){
if [[ -n $hy2_obfs ]]; then
    echo "  obfs: salamander"
    echo "  obfs-password: \"$hy2_obfs\""
fi
}

clhy2ports(){
if [[ -n $hy2_ports ]]; then
    echo "  ports: $cmhy2pt"
    echo "  hop-interval: $hy2_hop"
fi
}

clhy2bw(){
if [[ -n $hy2_up && -n $hy2_down ]]; then
    echo "  up: \"$hy2_up Mbps\""
    echo "  down: \"$hy2_down Mbps\""
fi
}

# 生成单个 sing-box VLESS 出站节点
sb_node_vless(){
local srv="$1" ntag="$2"
cat <<EOF
    {
      "type": "vless",
      "tag": "$ntag",
      "server": "$srv",
      "server_port": $vl_port,
      "uuid": "$uuid",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$vl_name",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "$public_key",
          "short_id": "$short_id"
        }
      }
    },
EOF
}

# 生成单个 sing-box VMess 出站节点
sb_node_vmess(){
local srv="$1" port="$2" ntag="$3" tls_en="$4" host_sni="$5"
cat <<EOF
    {
      "server": "$srv",
      "server_port": $port,
      "tag": "$ntag",
$(sbvmess_tls "$tls_en" "$host_sni")
      "transport": {
        "headers": {
          "Host": [
            "$host_sni"
          ]
        },
        "path": "$ws_path",
        "type": "ws"
      },
      "type": "vmess",
      "security": "auto",
      "uuid": "$uuid"
    },
EOF
}

# 生成单个 sing-box Hysteria2 出站节点
sb_node_hy2(){
local srv="$1" ntag="$2"
cat <<EOF
    {
      "type": "hysteria2",
      "tag": "$ntag",
      "server": "$srv",
$(sbhy2ports)
$(sbhy2obfs)
$(sbhy2bw)
      "password": "$uuid",
      "tls": {
        "enabled": true,
        "server_name": "$hy2_name",
        "insecure": $hy2_ins,
        "alpn": [
          "h3"
        ]
      }
    },
EOF
}

# 生成单个 sing-box TUIC5 出站节点
sb_node_tuic5(){
local srv="$1" ntag="$2"
cat <<EOF
    {
      "type": "tuic",
      "tag": "$ntag",
      "server": "$srv",
      "server_port": $tu5_port,
      "uuid": "$uuid",
      "password": "$uuid",
      "congestion_control": "bbr",
      "udp_relay_mode": "native",
      "udp_over_stream": false,
      "zero_rtt_handshake": false,
      "heartbeat": "10s",
      "tls": {
        "enabled": true,
        "server_name": "$tu5_name",
        "insecure": $tu5_ins,
        "alpn": [
          "h3"
        ]
      }
    },
EOF
}

# 生成单个 sing-box AnyTLS 出站节点（server 严格使用纯 IP 或域名，不带方括号）
sb_node_anytls(){
local srv="$1" ntag="$2"
cat <<EOF
    {
      "type": "anytls",
      "tag": "$ntag",
      "server": "$srv",
      "server_port": $an_port,
      "password": "$uuid",
      "idle_session_check_interval": "30s",
      "idle_session_timeout": "30s",
      "min_idle_session": 5,
      "tls": {
        "enabled": true,
        "insecure": $an_ins,
        "server_name": "$an_name"
      }
    },
EOF
}

# 将节点 tag 列表格式化为严格合法的 JSON 字符串数组项（末项无逗号）
sb_json_tags(){
local arr=("$@") i last=$((${#arr[@]} - 1))
for i in "${!arr[@]}"; do
if (( i < last )); then
printf '        "%s",\n' "${arr[$i]}"
else
printf '        "%s"\n' "${arr[$i]}"
fi
done
}

# 生成单个 Mihomo/Clash 节点（所有字符串字段严格使用双引号包裹，防止 IPv6 冒号引发 YAML 语法错误）
cl_node_vless(){
local srv="$1" nname="$2"
cat <<EOF
- name: "$nname"
  type: vless
  server: "$srv"
  port: $vl_port
  uuid: "$uuid"
  network: tcp
  udp: true
  tls: true
  flow: xtls-rprx-vision
  servername: "$vl_name"
  reality-opts:
    public-key: "$public_key"
    short-id: "$short_id"
  client-fingerprint: chrome

EOF
}

cl_node_vmess(){
local srv="$1" port="$2" nname="$3" tls_en="$4" host_sni="$5"
cat <<EOF
- name: "$nname"
  type: vmess
  server: "$srv"
  port: $port
  uuid: "$uuid"
  alterId: 0
  cipher: auto
  udp: true
  tls: $tls_en
  network: ws
  servername: "$host_sni"
  ws-opts:
    path: "$ws_path"
    headers:
      Host: "$host_sni"

EOF
}

cl_node_hy2(){
local srv="$1" nname="$2"
cat <<EOF
- name: "$nname"
  type: hysteria2
  server: "$srv"
  port: $hy2_port
$(clhy2ports)
  password: "$uuid"
$(clhy2obfs)
$(clhy2bw)
  alpn:
    - h3
  sni: "$hy2_name"
  skip-cert-verify: $hy2_ins
  fast-open: true

EOF
}

cl_node_tuic5(){
local srv="$1" nname="$2"
cat <<EOF
- name: "$nname"
  server: "$srv"
  port: $tu5_port
  type: tuic
  uuid: "$uuid"
  password: "$uuid"
  alpn: [h3]
  disable-sni: false
  reduce-rtt: true
  udp-relay-mode: native
  congestion-controller: bbr
  sni: "$tu5_name"
  skip-cert-verify: $tu5_ins

EOF
}

cl_node_anytls(){
local srv="$1" nname="$2"
cat <<EOF
- name: "$nname"
  type: anytls
  server: "$srv"
  port: $an_port
  password: "$uuid"
  client-fingerprint: chrome
  udp: true
  idle-session-check-interval: 30
  idle-session-timeout: 30
  sni: "$an_name"
  skip-cert-verify: $an_ins

EOF
}

# 将节点名称列表格式化为 Mihomo proxy-groups 的 proxies 条目
cl_yaml_proxies(){
local n
for n in "$@"; do
printf '    - "%s"\n' "$n"
done
}

# 检测 Argo 固定与临时隧道运行状态
local has_argo_gd=0 has_argo_ls=0
tls=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
ps -ef 2>/dev/null | grep -q '[c]loudflared.*run' && has_argo_gd=1
ps -ef 2>/dev/null | grep "[l]ocalhost:${vm_port}" >/dev/null 2>&1 && has_argo_ls=1
fi

# 汇总 sing-box 与 Mihomo 节点定义及节点名称列表（双栈自动展开 -v4 / -v6）
local sb_nodes_buf="" cl_nodes_buf="" i ip tag
local sb_node_tags=() cl_node_names=()

# 1. VLESS Reality（始终直连 VPS IP）
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
sb_nodes_buf+="$(sb_node_vless "$ip" "vless-$hostname$tag")"$'\n'
sb_node_tags+=("vless-$hostname$tag")
cl_nodes_buf+="$(cl_node_vless "$ip" "vless-reality-vision-$hostname$tag")"$'\n'
cl_node_names+=("vless-reality-vision-$hostname$tag")
done

# 2. VMess WS
if [[ "$vm_is_direct_ip" = "1" ]]; then
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
sb_nodes_buf+="$(sb_node_vmess "$ip" "$vm_port" "vmess-$hostname$tag" "$tls" "$vm_name")"$'\n'
sb_node_tags+=("vmess-$hostname$tag")
cl_nodes_buf+="$(cl_node_vmess "$ip" "$vm_port" "vmess-ws-$hostname$tag" "$tls" "$vm_name")"$'\n'
cl_node_names+=("vmess-ws-$hostname$tag")
done
else
sb_nodes_buf+="$(sb_node_vmess "$vmadd_local" "$vm_port" "vmess-$hostname" "$tls" "$vm_name")"$'\n'
sb_node_tags+=("vmess-$hostname")
cl_nodes_buf+="$(cl_node_vmess "$vmadd_local" "$vm_port" "vmess-ws-$hostname" "$tls" "$vm_name")"$'\n'
cl_node_names+=("vmess-ws-$hostname")
fi

# 3. Hysteria2
if [[ "$hy2_is_direct_ip" = "1" ]]; then
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
sb_nodes_buf+="$(sb_node_hy2 "$ip" "hy2-$hostname$tag")"$'\n'
sb_node_tags+=("hy2-$hostname$tag")
cl_nodes_buf+="$(cl_node_hy2 "$ip" "hysteria2-$hostname$tag")"$'\n'
cl_node_names+=("hysteria2-$hostname$tag")
done
else
sb_nodes_buf+="$(sb_node_hy2 "$cl_hy2_ip" "hy2-$hostname")"$'\n'
sb_node_tags+=("hy2-$hostname")
cl_nodes_buf+="$(cl_node_hy2 "$cl_hy2_ip" "hysteria2-$hostname")"$'\n'
cl_node_names+=("hysteria2-$hostname")
fi

# 4. TUIC5
if [[ "$tu5_is_direct_ip" = "1" ]]; then
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
sb_nodes_buf+="$(sb_node_tuic5 "$ip" "tuic5-$hostname$tag")"$'\n'
sb_node_tags+=("tuic5-$hostname$tag")
cl_nodes_buf+="$(cl_node_tuic5 "$ip" "tuic5-$hostname$tag")"$'\n'
cl_node_names+=("tuic5-$hostname$tag")
done
else
sb_nodes_buf+="$(sb_node_tuic5 "$cl_tu5_ip" "tuic5-$hostname")"$'\n'
sb_node_tags+=("tuic5-$hostname")
cl_nodes_buf+="$(cl_node_tuic5 "$cl_tu5_ip" "tuic5-$hostname")"$'\n'
cl_node_names+=("tuic5-$hostname")
fi

# 5. AnyTLS（仅 sing-box 1.11+ 支持）
if [[ "$sbnh" != "1.10" ]]; then
if [[ "$an_is_direct_ip" = "1" ]]; then
for i in "${!server_ips_list[@]}"; do
ip="${server_ips_list[$i]}"
tag="${server_ip_tags[$i]}"
sb_nodes_buf+="$(sb_node_anytls "$ip" "anytls-$hostname$tag")"$'\n'
sb_node_tags+=("anytls-$hostname$tag")
cl_nodes_buf+="$(cl_node_anytls "$ip" "anytls-$hostname$tag")"$'\n'
cl_node_names+=("anytls-$hostname$tag")
done
else
sb_nodes_buf+="$(sb_node_anytls "$cl_an_ip" "anytls-$hostname")"$'\n'
sb_node_tags+=("anytls-$hostname")
cl_nodes_buf+="$(cl_node_anytls "$cl_an_ip" "anytls-$hostname")"$'\n'
cl_node_names+=("anytls-$hostname")
fi
fi

# 6. Argo 固定隧道节点
if [[ "$has_argo_gd" = "1" ]]; then
sb_nodes_buf+="$(sb_node_vmess "$vmadd_argo" 443 "vmess-tls-argo固定-$hostname" "true" "$argogd")"$'\n'
sb_nodes_buf+="$(sb_node_vmess "$vmadd_argo" 8880 "vmess-argo固定-$hostname" "false" "$argogd")"$'\n'
sb_node_tags+=("vmess-tls-argo固定-$hostname" "vmess-argo固定-$hostname")
cl_nodes_buf+="$(cl_node_vmess "$vmadd_argo" 443 "vmess-tls-argo固定-$hostname" "true" "$argogd")"$'\n'
cl_nodes_buf+="$(cl_node_vmess "$vmadd_argo" 8880 "vmess-argo固定-$hostname" "false" "$argogd")"$'\n'
cl_node_names+=("vmess-tls-argo固定-$hostname" "vmess-argo固定-$hostname")
fi

# 7. Argo 临时隧道节点
if [[ "$has_argo_ls" = "1" ]]; then
sb_nodes_buf+="$(sb_node_vmess "$vmadd_argo" 443 "vmess-tls-argo临时-$hostname" "true" "$argo")"$'\n'
sb_nodes_buf+="$(sb_node_vmess "$vmadd_argo" 8880 "vmess-argo临时-$hostname" "false" "$argo")"$'\n'
sb_node_tags+=("vmess-tls-argo临时-$hostname" "vmess-argo临时-$hostname")
cl_nodes_buf+="$(cl_node_vmess "$vmadd_argo" 443 "vmess-tls-argo临时-$hostname" "true" "$argo")"$'\n'
cl_nodes_buf+="$(cl_node_vmess "$vmadd_argo" 8880 "vmess-argo临时-$hostname" "false" "$argo")"$'\n'
cl_node_names+=("vmess-tls-argo临时-$hostname" "vmess-argo临时-$hostname")
fi

# 写入 sing-box 客户端配置 /etc/s-box/sbox.json
cat > /etc/s-box/sbox.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "http_clients": [
    {
      "tag": "rule-set-direct"
    }
  ],
  "dns": {
    "servers": [
      {
        "type": "fakeip",
        "tag": "fakeip",
        "inet4_range": "198.18.0.0/15",
        "inet6_range": "fc00::/18"
      },
      {
        "type": "udp",
        "tag": "dns-cn",
        "server": "223.5.5.5",
        "server_port": 53
      },
      {
        "type": "https",
        "tag": "dns-proxy",
        "server": "dns.google",
        "domain_resolver": "dns-cn",
        "detour": "proxy"
      }
    ],
    "rules": [
      {
        "rule_set": [
          "geosite-cn"
        ],
        "action": "route",
        "server": "dns-cn"
      },
      {
        "query_type": [
          "A",
          "AAAA"
        ],
        "action": "route",
        "server": "fakeip"
      }
    ],
    "final": "dns-proxy",
    "strategy": "prefer_ipv4",
    "cache_capacity": 8192,
    "optimistic": {
      "enabled": true,
      "timeout": "1h"
    },
    "timeout": "10s",
    "reverse_mapping": true
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": [
        "172.19.0.1/30",
        "fdfe:dcba:9876::1/126"
      ],
      "auto_route": true,
      "strict_route": true,
      "stack": "gvisor",
      "mtu": 1420
    }
  ],
  "route": {
    "default_http_client": "rule-set-direct",
    "default_domain_resolver": "dns-cn",
    "auto_detect_interface": true,
    "rule_set": [
      {
        "tag": "geosite-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geosite/cn.srs"
      },
      {
        "tag": "geoip-cn",
        "type": "remote",
        "format": "binary",
        "url": "https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@sing/geo/geoip/cn.srs"
      }
    ],
    "rules": [
      {
        "action": "sniff"
      },
      {
        "inbound": [
          "tun-in"
        ],
        "protocol": [
          "dns"
        ],
        "action": "hijack-dns"
      },
      {
        "clash_mode": "Global",
        "action": "route",
        "outbound": "proxy"
      },
      {
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geosite-cn"
        ],
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geoip-cn"
        ],
        "action": "route",
        "outbound": "direct"
      },
      {
        "clash_mode": "Direct",
        "action": "route",
        "outbound": "direct"
      },
      {
        "network": [
          "tcp",
          "udp"
        ],
        "port": 853,
        "action": "reject"
      }
    ],
    "final": "proxy"
  },
  "experimental": {
    "cache_file": {
      "enabled": true,
      "store_dns": true
    },
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "external_ui": "ui",
      "default_mode": "Rule"
    }
  },
  "outbounds": [
${sb_nodes_buf}    {
      "tag": "proxy",
      "type": "selector",
      "default": "auto",
      "outbounds": [
$(sb_json_tags "auto" "${sb_node_tags[@]}")
      ]
    },
    {
      "tag": "auto",
      "type": "urltest",
      "outbounds": [
$(sb_json_tags "${sb_node_tags[@]}")
      ],
      "url": "http://www.gstatic.com/generate_204",
      "interval": "10m",
      "tolerance": 30,
      "idle_timeout": "30m"
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

# 写入 Mihomo/Clash 客户端配置 /etc/s-box/clmi.yaml
cat > /etc/s-box/clmi.yaml <<EOF
port: 7890
allow-lan: true
mode: rule
log-level: info
unified-delay: true
dns:
  enable: true
  listen: "0.0.0.0:1053"
  ipv6: true
  prefer-h3: false
  respect-rules: true
  use-system-hosts: false
  cache-algorithm: "arc"
  enhanced-mode: "fake-ip"
  fake-ip-range: "198.18.0.1/16"
  fake-ip-filter:
    - "+.lan"
    - "+.local"
    - "+.msftconnecttest.com"
    - "+.msftncsi.com"
    - "localhost.ptlogin2.qq.com"
    - "localhost.sec.qq.com"
    - "+.in-addr.arpa"
    - "+.ip6.arpa"
    - "time.*.com"
    - "time.*.gov"
    - "pool.ntp.org"
    - "localhost.work.weixin.qq.com"
  default-nameserver: ["223.5.5.5", "119.29.29.29"]
  nameserver:
    - "https://1.1.1.1/dns-query"
    - "https://8.8.8.8/dns-query"
  proxy-server-nameserver:
    - "https://223.5.5.5/dns-query"
    - "https://doh.pub/dns-query"

proxies:
${cl_nodes_buf}
proxy-groups:
- name: 负载均衡
  type: load-balance
  url: https://www.gstatic.com/generate_204
  interval: 300
  strategy: round-robin
  proxies:
$(cl_yaml_proxies "${cl_node_names[@]}")

- name: 自动选择
  type: url-test
  url: https://www.gstatic.com/generate_204
  interval: 300
  tolerance: 50
  proxies:
$(cl_yaml_proxies "${cl_node_names[@]}")

- name: 🌍选择代理节点
  type: select
  proxies:
    - 负载均衡
    - 自动选择
    - DIRECT
$(cl_yaml_proxies "${cl_node_names[@]}")

rules:
  - GEOIP,LAN,DIRECT
  - GEOSITE,CN,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,🌍选择代理节点
EOF
}

cfargo_ym(){
tls=$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
echo
yellow "1：添加或者删除Argo临时隧道"
yellow "2：添加或者删除Argo固定隧道"
yellow "0：返回上层"
readp "请选择【0-2】：" menu
if [ "$menu" = "1" ]; then
cfargo
elif [ "$menu" = "2" ]; then
cfargoym
else
changeserv
fi
else
yellow "因vmess开启了tls，Argo隧道功能不可用" && sleep 2
fi
}

cloudflaredargo(){
if [ ! -e /etc/s-box/cloudflared ]; then
local cf_arch
case $(uname -m) in
aarch64) cf_arch=arm64;;
x86_64) cf_arch=amd64;;
armv7l) cf_arch=arm;;
*) red "cloudflared 暂不支持当前架构 $(uname -m)" && return 1;;
esac
if ! curl -fL -o /etc/s-box/cloudflared -# --retry 2 --connect-timeout 10 "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$cf_arch"; then
rm -f /etc/s-box/cloudflared
red "cloudflared 下载失败，请检查网络" && return 1
fi
chmod +x /etc/s-box/cloudflared
fi
}

cfargoym(){
echo
if [[ -f /etc/s-box/sbargotoken.log && -f /etc/s-box/sbargoym.log ]]; then
green "当前Argo固定隧道域名：$(cat /etc/s-box/sbargoym.log 2>/dev/null)"
green "当前Argo固定隧道Token：$(cat /etc/s-box/sbargotoken.log 2>/dev/null)"
fi
echo
green "请进入Cloudflare官网 --- Zero Trust --- 网络 --- 连接器，创建固定隧道"
yellow "1：重置/设置Argo固定隧道域名"
yellow "2：停止Argo固定隧道"
yellow "0：返回上层"
readp "请选择【0-2】：" menu
if [ "$menu" = "1" ]; then
cloudflaredargo || return 1
readp "输入Argo固定隧道Token: " argotoken
readp "输入Argo固定隧道域名: " argoym
if [[ -z "${argotoken}" || -z "${argoym}" ]]; then
red "Token 和域名均不能为空，已取消设置" && return 1
fi
vm_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].listen_port')
echo
yellow "注意！Zero Trust设置固定隧道URL端口填写Vmess端口：localhost:$vm_port"
echo
pid=$(ps -ef 2>/dev/null | awk '/[c]loudflared.*run/ {print $2}')
[ -n "$pid" ] && kill -9 "$pid" >/dev/null 2>&1
echo
if pidof systemd >/dev/null 2>&1; then
cat > /etc/systemd/system/argo.service <<EOF
[Unit]
Description=argo service
After=network.target
[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=/etc/s-box/cloudflared tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token "${argotoken}"
Restart=on-failure
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload >/dev/null 2>&1
systemctl enable argo >/dev/null 2>&1
systemctl restart argo >/dev/null 2>&1
elif command -v rc-service >/dev/null 2>&1; then
cat > /etc/init.d/argo <<EOF
#!/sbin/openrc-run
description="argo service"
command="/etc/s-box/cloudflared"
command_args="tunnel --no-autoupdate --edge-ip-version auto --protocol http2 run --token ${argotoken}"
pidfile="/run/argo.pid"
command_background="yes"
depend() {
need net
}
EOF
chmod +x /etc/init.d/argo >/dev/null 2>&1
rc-update add argo default >/dev/null 2>&1
rc-service argo restart >/dev/null 2>&1
fi
echo "${argoym}" > /etc/s-box/sbargoym.log
echo "${argotoken}" > /etc/s-box/sbargotoken.log
argosh=$(cat /etc/s-box/sbargoym.log 2>/dev/null)
sbshare > /dev/null 2>&1
blue "Argo固定隧道设置完成，固定域名：$argosh"
elif [ "$menu" = "2" ]; then
if pidof systemd >/dev/null 2>&1; then
systemctl stop argo >/dev/null 2>&1
systemctl disable argo >/dev/null 2>&1
rm -rf /etc/systemd/system/argo.service
elif command -v rc-service >/dev/null 2>&1; then
rc-service argo stop >/dev/null 2>&1
rc-update del argo default >/dev/null 2>&1
rm -rf /etc/init.d/argo
fi
rm -rf /etc/s-box/vm_ws_argogd.txt
sbshare > /dev/null 2>&1
green "Argo固定隧道已停止"
else
cfargo_ym
fi
}

cfargo(){
echo
yellow "1：重置Argo临时隧道域名"
yellow "2：停止Argo临时隧道"
yellow "0：返回上层"
readp "请选择【0-2】：" menu
if [ "$menu" = "1" ]; then
green "请稍等……"
cloudflaredargo || return 1
ps -ef | grep "[c]loudflared tunnel --url http://localhost:" | awk '{print $2}' | xargs kill 2>/dev/null
vm_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].listen_port')
nohup /etc/s-box/cloudflared tunnel --url "http://localhost:${vm_port}" --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
sleep 15
argo=$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')
if [[ -n "$argo" && -n $(curl -sL --connect-timeout 3 -m 8 "https://${argo}/" -I | awk 'NR==1 && /404|400|503/') ]]; then
sbshare > /dev/null 2>&1
blue "Argo临时隧道申请成功，域名验证有效：$argo" && sleep 2
if command -v apk >/dev/null 2>&1; then
cat > /etc/local.d/alpineargo.start <<'EOF'
#!/bin/bash
sleep 10
vm_p=$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json 2>/dev/null | jq -r '.inbounds[1].listen_port')
nohup /etc/s-box/cloudflared tunnel --url "http://localhost:${vm_p}" --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 &
sleep 10
printf "9\n1\n" | bash /usr/bin/sb > /dev/null 2>&1
EOF
chmod +x /etc/local.d/alpineargo.start
rc-update add local default >/dev/null 2>&1
else
cron_update 'cloudflared tunnel --url http' '@reboot sleep 10 && /bin/bash -c "nohup /etc/s-box/cloudflared tunnel --url http://localhost:$(jq -r .inbounds[1].listen_port /etc/s-box/sb.json) --edge-ip-version auto --no-autoupdate --protocol http2 > /etc/s-box/argo.log 2>&1 & sleep 10 && printf \"9\n1\n\" | bash /usr/bin/sb > /dev/null 2>&1"'
fi
else
yellow "Argo临时域名验证暂不可用，请稍后再试"
fi
elif [ "$menu" = "2" ]; then
ps -ef | grep "[c]loudflared tunnel --url http://localhost:" | awk '{print $2}' | xargs kill 2>/dev/null
cron_update 'cloudflared tunnel --url http'
cron_update 'url http'
rm -rf /etc/s-box/vm_ws_argols.txt
rm -rf /etc/local.d/alpineargo.start
sbshare > /dev/null 2>&1
green "Argo临时隧道已停止"
else
cfargo_ym
fi
}

instsllsingbox(){
if sb_has_installed; then
red "已安装Sing-box服务，无法再次安装" && exit
fi
mkdir -p /etc/s-box
v6
openyn
sbnatprune
inssb
inscertificate
insport
if [[ "$AUTO" == "1" ]]; then
_auto_try=0
while :; do
if [[ $_auto_try -lt 50 ]]; then
port_hy2=$(shuf -i 50000-60000 -n 1)
else
port_hy2=$(shuf -i 10000-65535 -n 1)
fi
_auto_try=$((_auto_try + 1))
[[ "$port_hy2" != "$port_vl_re" && "$port_hy2" != "$port_vm_ws" && "$port_hy2" != "$port_an" ]] || continue
[[ -z $(ss -tunlp 2>/dev/null | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_hy2") ]] || continue
sbnatconflict "$port_hy2" "$port_hy2" >/dev/null && continue
break
done
_auto_try=0
while :; do
if [[ $_auto_try -lt 50 ]]; then
port_tu=$(shuf -i 40000-49999 -n 1)
else
port_tu=$(shuf -i 10000-65535 -n 1)
fi
_auto_try=$((_auto_try + 1))
[[ "$port_tu" != "$port_vl_re" && "$port_tu" != "$port_vm_ws" && "$port_tu" != "$port_an" && "$port_tu" != "$port_hy2" ]] || continue
[[ -z $(ss -tunlp 2>/dev/null | awk '{print $5}' | sed 's/.*://g' | grep -w "$port_tu") ]] || continue
sbnatconflict "$port_tu" "$port_tu" >/dev/null && continue
break
done
blue "自动模式已为Hy2选定主端口：$port_hy2，Tuic选定主端口：$port_tu"
fi
sleep 2
echo
blue "Vless-reality相关key与id将自动生成……"
key_pair=$(/etc/s-box/sing-box generate reality-keypair)
private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
echo "$public_key" > /etc/s-box/public.key
short_id=$(/etc/s-box/sing-box generate rand --hex 4)
wget -q -O /root/geoip.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.db
wget -q -O /root/geosite.db https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.db
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "五、自动生成warp-wireguard出站账户" && sleep 2
warpwg
inssbjsonser
sbservice
sbactive
if [[ "$AUTO" == "1" ]]; then
if natmsg=$(sbnatconflict 50000 60000 "$port_hy2"); then
yellow "跳过自动添加 Hy2 端口跳跃 (50000-60000)：$natmsg"
else
sbnatclr 50000:60000
sbnatadd 50000:60000 "$port_hy2"
blue "已自动为Hysteria2添加端口跳跃范围：50000-60000"
fi
if natmsg=$(sbnatconflict 40000 49999 "$port_tu"); then
yellow "跳过自动添加 Tuic5 端口跳跃 (40000-49999)：$natmsg"
else
sbnatclr 40000:49999
sbnatadd 40000:49999 "$port_tu"
blue "已自动为Tuic5添加端口跳跃范围：40000-49999"
fi
sbfwsave
fi
if [[ "$fwact" = "1" ]]; then
sbfwopen
else
sbfwsave
fi
curl -sL --connect-timeout 3 -m 6 https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
lnsb && blue "Sing-box-yg脚本安装成功，脚本快捷方式：sb" && cronsb
echo
wgcfgo
sbshare
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
blue "可选择9，刷新并显示所有协议配置及分享链接"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
}

changeym(){
[ -f /root/ygkkkca/ca.log ] && ymzs="$yellow切换为域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)$plain" || ymzs="$yellow未申请域名证书，无法切换$plain"
vl_na="正在使用的域名：$(sbjq_read /etc/s-box/sb.json '.inbounds[0].tls.server_name')。$yellow更换符合reality要求的域名，不支持证书域名$plain"
tls=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].tls.enabled')
[[ "$tls" = "false" ]] && vm_na="当前已关闭TLS。$ymzs ${yellow}将开启TLS，Argo隧道将不支持开启${plain}" || vm_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为关闭TLS，Argo隧道将可用$plain"
hy2_sniname=$(sbjq_read /etc/s-box/sb.json '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_na="正在使用自签bing证书。$ymzs" || hy2_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
tu5_sniname=$(sbjq_read /etc/s-box/sb.json '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_na="正在使用自签bing证书。$ymzs" || tu5_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
an_sniname=$(sbjq_read /etc/s-box/sb.json '.inbounds[4].tls.key_path // empty')
[[ "$an_sniname" = '/etc/s-box/private.key' ]] && an_na="正在使用自签bing证书。$ymzs" || an_na="正在使用的域名证书：$(cat /root/ygkkkca/ca.log 2>/dev/null)。$yellow切换为自签bing证书$plain"
echo
green "请选择要切换证书模式的协议"
green "1：vless-reality协议，$vl_na"
if [[ -s /root/ygkkkca/ca.log ]]; then
green "2：vmess-ws协议，$vm_na"
green "3：Hysteria2协议，$hy2_na"
green "4：Tuic5协议，$tu5_na"
if [[ "$sbnh" != "1.10" ]]; then
green "5：Anytls协议，$an_na"
fi
else
red "仅支持选项1 (vless-reality)。因未申请域名证书，vmess-ws、Hysteria-2、Tuic-v5、Anytls的证书切换选项暂不予显示"
fi
green "0：返回上层"
readp "请选择：" menu
if [ "$menu" = "1" ]; then
readp "请输入vless-reality域名 (回车使用apple.com)：" menu
ym_vl_re=${menu:-apple.com}
sbjq_edit_all --arg sni "$ym_vl_re" '(.inbounds[] | select(.tag == "vless-sb") | .tls) |= (.server_name = $sni | .reality.handshake.server = $sni)'
restartsb && sbshare > /dev/null 2>&1
blue "Vless-reality域名证书更换完毕"
elif [ "$menu" = "2" ]; then
if [ -s /root/ygkkkca/ca.log ]; then
a=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].tls.enabled')
if [ "$a" = "true" ]; then
a_a=false
b_b="www.bing.com"
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
else
a_a=true
b_b=$(cat /root/ygkkkca/ca.log)
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
fi
sbjq_edit_all --argjson en "$a_a" --arg sni "$b_b" --arg cert "$c_c" --arg key "$d_d" \
  '(.inbounds[] | select(.tag == "vmess-sb") | .tls) |= (.enabled = $en | .server_name = $sni | .certificate_path = $cert | .key_path = $key)'
restartsb && sbshare > /dev/null 2>&1
blue "vmess-ws协议域名证书更换完毕"
echo
tls=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].tls.enabled')
vm_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].listen_port')
blue "当前Vmess-ws(tls)的端口：$vm_port"
[[ "$tls" = "false" ]] && blue "切记：可进入主菜单选项4-2，将Vmess-ws端口更改为任意7个80系端口(80、8080、8880、2052、2082、2086、2095)，可实现CDN优选IP" || blue "切记：可进入主菜单选项4-2，将Vmess-ws-tls端口更改为任意6个443系的端口(443、8443、2053、2083、2087、2096)，可实现CDN优选IP"
echo
else
red "当前未申请域名证书，不可切换。主菜单选择12，执行Acme证书申请" && sleep 2 && sb
fi
elif [ "$menu" = "3" ]; then
if [ -s /root/ygkkkca/ca.log ]; then
d=$(sbjq_read /etc/s-box/sb.json '.inbounds[2].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
sbjq_edit_all --arg cert "$c_c" --arg key "$d_d" \
  '(.inbounds[] | select(.tag == "hy2-sb") | .tls) |= (.certificate_path = $cert | .key_path = $key)'
restartsb && sbshare > /dev/null 2>&1
blue "Hysteria2协议域名证书更换完毕"
else
red "当前未申请域名证书，不可切换。主菜单选择12，执行Acme证书申请" && sleep 2 && sb
fi
elif [ "$menu" = "4" ]; then
if [ -s /root/ygkkkca/ca.log ]; then
d=$(sbjq_read /etc/s-box/sb.json '.inbounds[3].tls.key_path')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
sbjq_edit_all --arg cert "$c_c" --arg key "$d_d" \
  '(.inbounds[] | select(.tag == "tuic5-sb") | .tls) |= (.certificate_path = $cert | .key_path = $key)'
restartsb && sbshare > /dev/null 2>&1
blue "Tuic5协议域名证书更换完毕"
else
red "当前未申请域名证书，不可切换。主菜单选择12，执行Acme证书申请" && sleep 2 && sb
fi
elif [ "$menu" = "5" ]; then
if [ -s /root/ygkkkca/ca.log ]; then
d=$(sbjq_read /etc/s-box/sb.json '.inbounds[4].tls.key_path // empty')
if [ "$d" = '/etc/s-box/private.key' ]; then
c_c='/root/ygkkkca/cert.crt'
d_d='/root/ygkkkca/private.key'
else
c_c='/etc/s-box/cert.pem'
d_d='/etc/s-box/private.key'
fi
sbjq_edit_all --arg cert "$c_c" --arg key "$d_d" \
  '(.inbounds[] | select(.tag == "anytls-sb") | .tls) |= (.certificate_path = $cert | .key_path = $key)'
restartsb && sbshare > /dev/null 2>&1
blue "Anytls协议域名证书更换完毕"
else
red "当前未申请域名证书，不可切换。主菜单选择12，执行Acme证书申请" && sleep 2 && sb
fi
else
sb
fi
}

allports(){
vl_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[0].listen_port')
vm_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].listen_port')
hy2_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[2].listen_port')
tu5_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[3].listen_port')
an_port=$(sbjq_read /etc/s-box/sb.json '.inbounds[4].listen_port // empty')
hy2_ports=$(sbnatports "$hy2_port")
tu5_ports=$(sbnatports "$tu5_port")
[[ -n $hy2_ports ]] && hy2zfport="$hy2_ports" || hy2zfport="未添加"
[[ -n $tu5_ports ]] && tu5zfport="$tu5_ports" || tu5zfport="未添加"
}

changeport(){
sbactive
allports
fports(){
readp "\n请输入转发的端口范围 (1000-65535范围内，格式为 小数字:大数字)：" rangeport
if [[ $rangeport =~ ^([1-9][0-9]{3,4}:[1-9][0-9]{3,4})$ ]]; then
b=${rangeport%%:*}
c=${rangeport##*:}
if [[ $b -ge 1000 && $b -le 65535 && $c -ge 1000 && $c -le 65535 && $b -lt $c ]]; then
if natmsg=$(sbnatconflict $b $c $port); then
red "端口范围冲突：$natmsg" && fports && return
fi
sbnatclr $rangeport
sbnatadd "$rangeport" "$port"
sbfwsave
blue "已确认转发的端口范围：$rangeport"
else
red "输入的端口范围不在有效范围内" && fports
fi
else
red "输入格式不正确。格式为 小数字:大数字" && fports
fi
echo
}
fport(){
readp "\n请输入一个转发的端口 (1000-65535范围内)：" onlyport
if [[ $onlyport =~ ^[1-9][0-9]{3,4}$ && $onlyport -ge 1000 && $onlyport -le 65535 ]]; then
if natmsg=$(sbnatconflict $onlyport $onlyport $port); then
red "端口冲突：$natmsg" && fport && return
fi
sbnatclr $onlyport
sbnatadd "$onlyport" "$port"
sbfwsave
blue "已确认转发的端口：$onlyport"
else
blue "输入的端口不在有效范围内" && fport
fi
echo
}

hy2deports(){
allports
local p t r
IFS=',' read -ra ports <<< "$hy2_ports"
for p in "${ports[@]}"; do
for t in iptables ip6tables; do
$t -t nat -S PREROUTING 2>/dev/null | grep -E -- "-p udp .*--dport $p .*(-j REDIRECT --to-ports $hy2_port|-j DNAT --to-destination (\[::\])?:$hy2_port)$" | while read -r r; do
eval "$t -t nat -D ${r#-A }" >/dev/null 2>&1
done
done
done
sbfwsave
}
tu5deports(){
allports
local p t r
IFS=',' read -ra ports <<< "$tu5_ports"
for p in "${ports[@]}"; do
for t in iptables ip6tables; do
$t -t nat -S PREROUTING 2>/dev/null | grep -E -- "-p udp .*--dport $p .*(-j REDIRECT --to-ports $tu5_port|-j DNAT --to-destination (\[::\])?:$tu5_port)$" | while read -r r; do
eval "$t -t nat -D ${r#-A }" >/dev/null 2>&1
done
done
done
sbfwsave
}

allports
green "Vless-reality、Vmess-ws、Anytls仅能更改唯一的端口，vmess-ws注意Argo端口重置"
green "Hysteria2与Tuic5支持更改主端口，也支持增删多个转发端口"
green "Hysteria2支持端口跳跃，且与Tuic5都支持多端口复用"
echo
green "1：Vless-reality协议 ${yellow}端口:$vl_port${plain}"
green "2：Vmess-ws协议 ${yellow}端口:$vm_port${plain}"
green "3：Hysteria2协议 ${yellow}端口:$hy2_port  转发多端口: $hy2zfport${plain}"
green "4：Tuic5协议 ${yellow}端口:$tu5_port  转发多端口: $tu5zfport${plain}"
if [[ "$sbnh" != "1.10" ]]; then
green "5：Anytls协议 ${yellow}端口:$an_port${plain}"
fi
green "0：返回上层"
readp "请选择要变更端口的协议：" menu
if [ "$menu" = "1" ]; then
vlport
sbjq_edit_all --argjson p "$port_vl_re" '(.inbounds[] | select(.tag == "vless-sb") | .listen_port) = $p'
sbfwre
restartsb && sbshare > /dev/null 2>&1
blue "Vless-reality端口更改完成"
echo
elif [ "$menu" = "5" ]; then
anport
sbjq_edit_all --argjson p "$port_an" '(.inbounds[] | select(.tag == "anytls-sb") | .listen_port) = $p'
sbfwre
restartsb && sbshare > /dev/null 2>&1
blue "Anytls端口更改完成"
echo
elif [ "$menu" = "2" ]; then
vmport
sbjq_edit_all --argjson p "$port_vm_ws" '(.inbounds[] | select(.tag == "vmess-sb") | .listen_port) = $p'
sbfwre
restartsb && sbshare > /dev/null 2>&1
blue "Vmess-ws端口更改完成"
tls=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
blue "切记：如果Argo使用中，临时隧道必须重置，固定隧道的CF设置界面端口必须修改为$port_vm_ws"
else
blue "因TLS已开启，当前Argo隧道已不支持开启"
fi
echo
elif [ "$menu" = "3" ]; then
green "1：更换Hysteria2主端口 (原多端口自动重置删除)"
green "2：添加Hysteria2多端口"
green "3：重置删除Hysteria2多端口"
green "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
if [ -n "$hy2_ports" ]; then
hy2deports
fi
hy2port
sbjq_edit_all --argjson p "$port_hy2" '(.inbounds[] | select(.tag == "hy2-sb") | .listen_port) = $p'
sbfwre
restartsb && sbshare > /dev/null 2>&1
blue "Hysteria2端口更改完成"
elif [ "$menu" = "2" ]; then
green "1：添加Hysteria2范围端口"
green "2：添加Hysteria2单端口"
green "0：返回上层"
readp "请选择【0-2】：" menu
port=$(sbjq_read /etc/s-box/sb.json '.inbounds[2].listen_port')
if [ "$menu" = "1" ]; then
fports && sbshare > /dev/null 2>&1 && changeport
elif [ "$menu" = "2" ]; then
fport && sbshare > /dev/null 2>&1 && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n "$hy2_ports" ]; then
hy2deports && sbshare > /dev/null 2>&1 && yellow "Hysteria2多端口已删除" && changeport
else
sbshare > /dev/null 2>&1 && yellow "Hysteria2未设置多端口" && changeport
fi
else
changeport
fi

elif [ "$menu" = "4" ]; then
green "1：更换Tuic5主端口 (原多端口自动重置删除)"
green "2：添加Tuic5多端口"
green "3：重置删除Tuic5多端口"
green "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
if [ -n "$tu5_ports" ]; then
tu5deports
fi
tu5port
sbjq_edit_all --argjson p "$port_tu" '(.inbounds[] | select(.tag == "tuic5-sb") | .listen_port) = $p'
sbfwre
restartsb && sbshare > /dev/null 2>&1
blue "Tuic5端口更改完成"
elif [ "$menu" = "2" ]; then
green "1：添加Tuic5范围端口"
green "2：添加Tuic5单端口"
green "0：返回上层"
readp "请选择【0-2】：" menu
port=$(sbjq_read /etc/s-box/sb.json '.inbounds[3].listen_port')
if [ "$menu" = "1" ]; then
fports && sbshare > /dev/null 2>&1 && changeport
elif [ "$menu" = "2" ]; then
fport && sbshare > /dev/null 2>&1 && changeport
else
changeport
fi
elif [ "$menu" = "3" ]; then
if [ -n "$tu5_ports" ]; then
tu5deports && sbshare > /dev/null 2>&1 && yellow "Tuic5多端口已删除" && changeport
else
sbshare > /dev/null 2>&1 && yellow "Tuic5未设置多端口" && changeport
fi
else
changeport
fi
else
sb
fi
}

changeuuid(){
echo
olduuid=$(sbjq_read /etc/s-box/sb.json '.inbounds[0].users[0].uuid')
oldvmpath=$(sbjq_read /etc/s-box/sb.json '.inbounds[1].transport.path')
green "全协议的uuid (密码)：$olduuid"
green "Vmess的path路径：$oldvmpath"
echo
yellow "1：自定义全协议的uuid (密码)"
yellow "2：自定义Vmess的path路径"
yellow "0：返回上层"
readp "请选择【0-2】：" menu
if [ "$menu" = "1" ]; then
readp "输入uuid，必须是uuid格式，不懂就回车(重置并随机生成uuid)：" menu
if [ -z "$menu" ]; then
uuid=$(/etc/s-box/sing-box generate uuid)
else
uuid=$menu
fi
# 按字段精确更新各协议的 uuid/password 及默认 path，避免全局 sed 误伤 JSON 结构
sbjq_edit_all --arg u "$uuid" --arg old "$olduuid" '
  (.inbounds[] | select(.tag == "vless-sb") | .users[0].uuid) = $u |
  (.inbounds[] | select(.tag == "vmess-sb") | .users[0].uuid) = $u |
  (.inbounds[] | select(.tag == "vmess-sb") | .transport.path) |= (if . == ($old + "-vm") then ($u + "-vm") else . end) |
  (.inbounds[] | select(.tag == "hy2-sb") | .users[0].password) = $u |
  (.inbounds[] | select(.tag == "tuic5-sb") | .users[0]) |= (.uuid = $u | .password = $u) |
  (.inbounds[] | select(.tag == "anytls-sb") | .users[0].password) = $u
'
restartsb && sbshare > /dev/null 2>&1
blue "已确认uuid (密码)：${uuid}"
blue "已确认Vmess的path路径：$(sbjq_read /etc/s-box/sb.json '.inbounds[1].transport.path')"
elif [ "$menu" = "2" ]; then
readp "输入Vmess的path路径，回车表示不变：" menu
if [ -z "$menu" ]; then
echo
else
vmpath=$menu
sbjq_edit_all --arg p "$vmpath" '(.inbounds[] | select(.tag == "vmess-sb") | .transport.path) = $p'
restartsb && sbshare > /dev/null 2>&1
fi
blue "已确认Vmess的path路径：$(sbjq_read /etc/s-box/sb.json '.inbounds[1].transport.path')"
else
changeserv
fi
}

changeip(){
if [[ "$sbnh" == "1.10" ]]; then
v4v6 force
chip(){
sbjq_edit /etc/s-box/sb10.json --arg ds "$rrpip" '(.outbounds[] | select(.tag == "direct") | .domain_strategy) = $ds'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
}
readp "1. IPV4优先\n2. IPV6优先\n3. 仅IPV4\n4. 仅IPV6\n请选择：" choose
if [[ $choose == "1" && -n $v4 ]]; then
rrpip="prefer_ipv4" && chip && v4_6="IPV4优先($v4)"
elif [[ $choose == "2" && -n $v6 ]]; then
rrpip="prefer_ipv6" && chip && v4_6="IPV6优先($v6)"
elif [[ $choose == "3" && -n $v4 ]]; then
rrpip="ipv4_only" && chip && v4_6="仅IPV4($v4)"
elif [[ $choose == "4" && -n $v6 ]]; then
rrpip="ipv6_only" && chip && v4_6="仅IPV6($v6)"
else
red "当前不存在你选择的IPV4/IPV6地址，或者输入错误" && changeip && return
fi
blue "当前已更换的IP优先级：${v4_6}" && sb
else
red "仅支持1.10.7内核可用" && exit
fi
}

tgsbshow(){
echo
yellow "1：重置/设置Telegram机器人的Token、用户ID"
yellow "0：返回上层"
readp "请选择【0-1】：" menu
if [ "$menu" = "1" ]; then
readp "输入Telegram机器人Token: " token
readp "输入Telegram机器人用户ID: " userid
if [[ -z "$token" || -z "$userid" ]]; then
red "Token 和用户 ID 均不能为空" && return 1
fi
rm -rf /etc/s-box/sbtg.sh
{
echo '#!/bin/bash'
echo 'export LANG=en_US.UTF-8'
printf 'TELEGRAM_TOKEN=%q\n' "$token"
printf 'TELEGRAM_ID=%q\n' "$userid"
cat <<'EOF'
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
total_lines=$(wc -l < /etc/s-box/clmi.yaml)
half=$((total_lines / 2))
head -n $half /etc/s-box/clmi.yaml > /etc/s-box/clash_meta_client1.txt
tail -n +$((half + 1)) /etc/s-box/clmi.yaml > /etc/s-box/clash_meta_client2.txt

total_lines=$(wc -l < /etc/s-box/sbox.json)
quarter=$((total_lines / 4))
head -n $quarter /etc/s-box/sbox.json > /etc/s-box/sing_box_client1.txt
tail -n +$((quarter + 1)) /etc/s-box/sbox.json | head -n $quarter > /etc/s-box/sing_box_client2.txt
tail -n +$((2 * quarter + 1)) /etc/s-box/sbox.json | head -n $quarter > /etc/s-box/sing_box_client3.txt
# 第 4 段不加 head 截断，避免总行数不能被 4 整除时丢失 JSON 结尾行
tail -n +$((3 * quarter + 1)) /etc/s-box/sbox.json > /etc/s-box/sing_box_client4.txt

m1=$(cat /etc/s-box/vl_reality.txt 2>/dev/null)
m2=$(cat /etc/s-box/vm_ws.txt 2>/dev/null)
m3=$(cat /etc/s-box/vm_ws_argols.txt 2>/dev/null)
m3_5=$(cat /etc/s-box/vm_ws_argogd.txt 2>/dev/null)
m4=$(cat /etc/s-box/vm_ws_tls.txt 2>/dev/null)
m5=$(cat /etc/s-box/hy2.txt 2>/dev/null)
m6=$(cat /etc/s-box/tuic5.txt 2>/dev/null)
m7=$(cat /etc/s-box/sing_box_client1.txt 2>/dev/null)
m7_5=$(cat /etc/s-box/sing_box_client2.txt 2>/dev/null)
m7_5_5=$(cat /etc/s-box/sing_box_client3.txt 2>/dev/null)
m7_5_5_5=$(cat /etc/s-box/sing_box_client4.txt 2>/dev/null)
m8=$(cat /etc/s-box/clash_meta_client1.txt 2>/dev/null)
m8_5=$(cat /etc/s-box/clash_meta_client2.txt 2>/dev/null)
m9=$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)
m10=$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)
m11=$(cat /etc/s-box/jhsub.txt 2>/dev/null)
m12=$(cat /etc/s-box/an.txt 2>/dev/null)

URL="https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage"
tg_send(){
res=$(timeout 20s curl -s -X POST "$URL" -d "chat_id=${TELEGRAM_ID}" --data-urlencode "text=$1")
rc=$?
}
tg_send "🚀【 Vless-reality-vision 分享链接 】：支持v2rayng、nekobox "$'\n\n'"${m1}"
if [[ -f /etc/s-box/vm_ws.txt ]]; then
tg_send "🚀【 Vmess-ws 分享链接 】：支持v2rayng、nekobox "$'\n\n'"${m2}"
fi
if [[ -f /etc/s-box/vm_ws_argols.txt ]]; then
tg_send "🚀【 Vmess-ws(tls)+Argo临时域名分享链接 】：支持v2rayng、nekobox "$'\n\n'"${m3}"
fi
if [[ -f /etc/s-box/vm_ws_argogd.txt ]]; then
tg_send "🚀【 Vmess-ws(tls)+Argo固定域名分享链接 】：支持v2rayng、nekobox "$'\n\n'"${m3_5}"
fi
if [[ -f /etc/s-box/vm_ws_tls.txt ]]; then
tg_send "🚀【 Vmess-ws-tls 分享链接 】：支持v2rayng、nekobox "$'\n\n'"${m4}"
fi
tg_send "🚀【 Hysteria-2 分享链接 】：支持v2rayng、nekobox "$'\n\n'"${m5}"
tg_send "🚀【 Tuic-v5 分享链接 】：支持nekobox "$'\n\n'"${m6}"
if [[ "$sbnh" != "1.10" ]]; then
tg_send "🚀【 Anytls 分享链接 】：仅最新内核可用 "$'\n\n'"${m12}"
fi
if [[ -f /etc/s-box/sing_box_gitlab.txt ]]; then
tg_send "🚀【 Sing-box 订阅链接 】：支持SFA、SFW、SFI "$'\n\n'"${m9}"
else
tg_send "🚀【 Sing-box 配置文件(4段) 】：支持SFA、SFW、SFI "$'\n\n'"${m7}"
tg_send "${m7_5}"
tg_send "${m7_5_5}"
tg_send "${m7_5_5_5}"
fi

if [[ -f /etc/s-box/clash_meta_gitlab.txt ]]; then
tg_send "🚀【 Mihomo 订阅链接 】：支持Mihomo相关客户端 "$'\n\n'"${m10}"
else
tg_send "🚀【 Mihomo 配置文件(2段) 】：支持Mihomo相关客户端 "$'\n\n'"${m8}"
tg_send "${m8_5}"
fi
tg_send "🚀【 聚合节点 】：支持nekobox "$'\n\n'"${m11}"

if [ "$rc" = "124" ]; then
echo "TG_api请求超时,请检查网络是否重启完成并是否能够访问TG"
fi
resSuccess=$(echo "$res" | jq -r ".ok" 2>/dev/null)
if [[ "$resSuccess" = "true" ]]; then
echo "TG推送成功"
else
echo "TG推送失败，请检查TG机器人Token和ID"
fi
EOF
} > /etc/s-box/sbtg.sh
chmod +x /etc/s-box/sbtg.sh
green "设置完成！请确保TG机器人已处于激活状态！"
tgnotice
else
changeserv
fi
}

tgnotice(){
if [[ -f /etc/s-box/sbtg.sh ]]; then
green "请稍等5秒，TG机器人准备推送……"
sbshare > /dev/null 2>&1
bash /etc/s-box/sbtg.sh
else
yellow "未设置TG通知功能"
fi
exit
}

changeserv(){
sbactive
echo
green "Sing-box配置变更选择如下:"
readp "1：更换Reality域名伪装地址、切换自签证书与Acme域名证书、开关TLS\n2：更换全协议UUID(密码)、Vmess-Path路径\n3：设置Argo临时隧道、固定隧道\n4：切换IPV4或IPV6的代理优先级 (仅 1.10.7 内核可用)\n5：设置Telegram推送节点通知\n6：更换Warp-wireguard出站账户\n7：设置Gitlab订阅分享链接\n8：设置本地IP订阅分享链接\n9：设置所有Vmess节点的CDN优选地址\n0：返回上层\n请选择【0-9】：" menu
if [ "$menu" = "1" ];then
changeym
elif [ "$menu" = "2" ];then
changeuuid
elif [ "$menu" = "3" ];then
cfargo_ym
elif [ "$menu" = "4" ];then
changeip
elif [ "$menu" = "5" ];then
tgsbshow
elif [ "$menu" = "6" ];then
changewg
elif [ "$menu" = "7" ];then
gitlabsub
elif [ "$menu" = "8" ];then
ipsub
elif [ "$menu" = "9" ];then
vmesscfadd
else 
sb
fi
}

ipsub(){
subtokenipsub(){
echo
local oldtok
oldtok=$(cat /etc/s-box/subtoken.log 2>/dev/null)
while :; do
readp "输入订阅链接路径密码（回车表示使用当前UUID，仅限字母/数字/._-）：" menu
if [ -z "$menu" ]; then
subtoken="$(sbjq_read /etc/s-box/sb.json '.inbounds[0].users[0].uuid')"
else
subtoken="$menu"
fi
if [[ "$subtoken" =~ ^[A-Za-z0-9._-]+$ && "$subtoken" != "." && "$subtoken" != ".." ]]; then
break
else
red "路径密码包含非法字符，仅允许字母、数字、点、下划线和短横线"
fi
done
if [[ -n "$oldtok" && "$oldtok" =~ ^[A-Za-z0-9._-]+$ && "$oldtok" != "." && "$oldtok" != ".." ]]; then
rm -rf "/root/websbox/$oldtok"
fi
echo "$subtoken" > /etc/s-box/subtoken.log
green "订阅链接路径密码：$(cat /etc/s-box/subtoken.log 2>/dev/null)"
}
subportipsub(){
echo
readp "输入未被占用且可用的订阅链接端口（回车表示随机端口）：" port
chooseport
subport="$port"
echo "$subport" > /etc/s-box/subport.log
green "订阅链接端口：$(cat /etc/s-box/subport.log 2>/dev/null)"
}
echo
yellow "1：重置安装本地IP订阅链接"
yellow "2：更换订阅链接路径密码"
yellow "3：更换订阅链接端口"
yellow "4：卸载本地IP订阅链接"
yellow "0：返回上层"
readp "请选择【0-4】：" menu
if [ "$menu" = "1" ]; then
subtokenipsub && subportipsub
elif [ "$menu" = "2" ];then
subtokenipsub
elif [ "$menu" = "3" ];then
subportipsub
elif [ "$menu" = "4" ];then
kill -15 $(pgrep -f 'websbox' 2>/dev/null) >/dev/null 2>&1
cron_update 'websbox'
rm -rf /root/websbox /etc/s-box/subport.log /etc/s-box/subtoken.log
rm -rf /etc/local.d/alpinesub.start
sbfwre
green "本地IP订阅链接已卸载完成" && sleep 2 && exit
else
changeserv
return
fi
echo
green "请稍后…………"
kill -15 $(pgrep -f 'websbox' 2>/dev/null) >/dev/null 2>&1
local curtok curport
curtok=$(cat /etc/s-box/subtoken.log 2>/dev/null)
curport=$(cat /etc/s-box/subport.log 2>/dev/null)
mkdir -p "/root/websbox/${curtok}"
ln -sf /etc/s-box/clmi.yaml "/root/websbox/${curtok}/clmi.yaml"
ln -sf /etc/s-box/sbox.json "/root/websbox/${curtok}/sbox.json"
ln -sf /etc/s-box/jhsub.txt "/root/websbox/${curtok}/jhsub.txt"
# 优先尝试 IPv6/双栈监听 [::]:port，若环境不支持则回退为默认监听
local httpd_bin="busybox" hpid
command -v apk >/dev/null 2>&1 && httpd_bin="busybox-extras"
$httpd_bin httpd -f -p "[::]:$curport" -h /root/websbox > /dev/null 2>&1 &
hpid=$!
sleep 0.5
if ! kill -0 "$hpid" 2>/dev/null; then
$httpd_bin httpd -f -p "$curport" -h /root/websbox > /dev/null 2>&1 &
fi
sleep 1.5
if command -v apk >/dev/null 2>&1; then
cat > /etc/local.d/alpinesub.start <<'EOF'
#!/bin/bash
sleep 10
p=$(cat /etc/s-box/subport.log 2>/dev/null)
busybox-extras httpd -f -p "[::]:$p" -h /root/websbox > /dev/null 2>&1 &
hpid=$!
sleep 0.5
if ! kill -0 "$hpid" 2>/dev/null; then busybox-extras httpd -f -p "$p" -h /root/websbox > /dev/null 2>&1 & fi
EOF
chmod +x /etc/local.d/alpinesub.start
rc-update add local default >/dev/null 2>&1
else
cron_update 'websbox' '@reboot sleep 10 && /bin/bash -c "p=\$(cat /etc/s-box/subport.log 2>/dev/null); busybox httpd -f -p \"[::]:\$p\" -h /root/websbox > /dev/null 2>&1 & hpid=\$!; sleep 0.5; if ! kill -0 \"\$hpid\" 2>/dev/null; then busybox httpd -f -p \"\$p\" -h /root/websbox > /dev/null 2>&1 & fi"'
fi
sbfwre
sbshare > /dev/null 2>&1
sleep 1 && green "本地IP订阅链接已更新完成" && sleep 2 && sb
}

vmesscfadd(){
echo
green "推荐使用稳定的世界大厂或组织的官方CDN域名作为CDN优选地址："
blue "cloudflare-ech.com"
blue "www.visa.com.sg"
blue "www.wto.org"
blue "www.shopify.com"
blue "yg1.ygkkk.dpdns.org (yg1中的1，可换为1-13中任意数字)"
echo
yellow "恢复默认操作：选项1/3回车可恢复默认，选项2重置host/sni域名"
echo
yellow "1：自定义Vmess-ws(tls)主协议节点的CDN优选地址"
yellow "2：针对选项1，重置客户端host/sni域名(IP解析到CF上的域名)"
yellow "3：自定义Vmess-ws(tls)-Argo节点的CDN优选地址"
yellow "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
echo
green "请确保VPS的IP已解析到Cloudflare的域名上"
if [[ ! -s /etc/s-box/cfymjx.txt ]]; then
readp "输入客户端host/sni域名(IP解析到CF上的域名，回车跳过)：" menu
[[ -n "$menu" ]] && echo "$menu" > /etc/s-box/cfymjx.txt
fi
echo
readp "输入自定义的优选IP/域名 (直接回车恢复默认)：" menu
if [[ -n "$menu" ]]; then
echo "$menu" > /etc/s-box/cfvmadd_local.txt
else
rm -f /etc/s-box/cfvmadd_local.txt
fi
sbshare > /dev/null 2>&1
green "设置成功，选择主菜单9进行节点配置更新" && sleep 2 && vmesscfadd
elif  [ "$menu" = "2" ]; then
rm -rf /etc/s-box/cfymjx.txt
sbshare > /dev/null 2>&1
green "重置成功，可选择1重新设置" && sleep 2 && vmesscfadd
elif  [ "$menu" = "3" ]; then
readp "输入自定义的优选IP/域名 (直接回车恢复默认)：" menu
if [[ -n "$menu" ]]; then
echo "$menu" > /etc/s-box/cfvmadd_argo.txt
else
rm -f /etc/s-box/cfvmadd_argo.txt
fi
sbshare > /dev/null 2>&1
green "设置成功，选择主菜单9进行节点配置更新" && sleep 2 && vmesscfadd
else
changeserv
fi
}

gitlabsub(){
echo
green "请确保Gitlab官网上已建立项目，已开启推送功能，已获取访问令牌"
yellow "1：重置/设置Gitlab订阅链接"
yellow "0：返回上层"
readp "请选择【0-1】：" menu
if [ "$menu" = "1" ]; then
cd /etc/s-box
readp "输入登录邮箱: " email
readp "输入访问令牌: " token
readp "输入用户名: " userid
readp "输入项目名: " project
if [[ -z "$email" || -z "$token" || -z "$userid" || -z "$project" ]]; then
red "邮箱、访问令牌、用户名和项目名均不能为空" && cd && return 1
fi
echo
green "多台VPS共用一个令牌及项目名，可创建多个分支订阅链接"
green "回车跳过表示不新建，仅使用主分支main订阅链接(首台VPS建议回车跳过)"
readp "新建分支名称: " gitlabml
echo
if [[ -z "$gitlabml" ]]; then
gitlab_ml=''
git_sk=main
rm -rf /etc/s-box/gitlab_ml_ml
else
gitlab_ml=":${gitlabml}"
git_sk="${gitlabml}"
echo "${gitlab_ml}" > /etc/s-box/gitlab_ml_ml
fi
echo "$token" > /etc/s-box/gitlabtoken.txt
rm -rf /etc/s-box/.git
git init >/dev/null 2>&1
git config --local user.email "${email}" >/dev/null 2>&1
git config --local user.name "${userid}" >/dev/null 2>&1
git add sbox.json clmi.yaml jhsub.txt >/dev/null 2>&1
git commit -m "commit_add_$(date +"%F %T")" >/dev/null 2>&1
branches=$(git branch)
if [[ $branches == *master* ]]; then
git branch -m master main >/dev/null 2>&1
fi
git remote add origin "https://oauth2:${token}@gitlab.com/${userid}/${project}.git" >/dev/null 2>&1
if [[ -d /etc/s-box/.git ]]; then
if GIT_TERMINAL_PROMPT=0 git push -f origin "main${gitlab_ml}" >/dev/null 2>&1; then
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/sbox.json/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/sing_box_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/clmi.yaml/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/clash_meta_gitlab.txt
echo "https://gitlab.com/api/v4/projects/${userid}%2F${project}/repository/files/jhsub.txt/raw?ref=${git_sk}&private_token=${token}" > /etc/s-box/jh_sub_gitlab.txt
clsbshow
else
yellow "推送至 Gitlab 失败，请检查访问令牌、用户名、项目名与网络连接"
fi
else
yellow "设置Gitlab订阅链接失败，请反馈"
fi
cd
else
changeserv
fi
}

gitlabsubgo(){
cd /etc/s-box
if [[ -d /etc/s-box/.git ]]; then
gitlab_ml=""
if [ -f /etc/s-box/gitlab_ml_ml ]; then
gitlab_ml=$(cat /etc/s-box/gitlab_ml_ml)
fi
git add sbox.json clmi.yaml jhsub.txt >/dev/null 2>&1
git commit --allow-empty -m "commit_update_$(date +"%F %T")" >/dev/null 2>&1
if GIT_TERMINAL_PROMPT=0 git push -f origin "main${gitlab_ml}" >/dev/null 2>&1; then
clsbshow
else
yellow "推送 Gitlab 订阅更新失败，请检查网络或重新设置 Gitlab 令牌"
fi
else
yellow "未设置Gitlab订阅链接"
fi
cd
}

clsbshow(){
green "当前Sing-box节点已更新并推送"
green "Sing-box订阅链接如下："
blue "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
green "Sing-box订阅链接二维码如下："
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/sing_box_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "当前Mihomo节点配置已更新并推送"
green "Mihomo订阅链接如下："
blue "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
green "Mihomo订阅链接二维码如下："
qrencode -o - -t ANSIUTF8 "$(cat /etc/s-box/clash_meta_gitlab.txt 2>/dev/null)"
echo
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
green "当前聚合节点配置已更新并推送"
green "订阅链接如下："
blue "$(cat /etc/s-box/jh_sub_gitlab.txt 2>/dev/null)"
echo
yellow "可以在网页上输入订阅链接查看配置内容，如果无配置内容，请自检Gitlab相关设置并重置"
echo
}

warpwg(){
# 使用 openssl + jq 直接注册并解析 WARP 账户，不再依赖 python3 / grep -P / 固定行号
local keypair priv_hex pub_hex priv_b64 pub_b64 response client_id res_hex r1 r2 r3
keypair=$(openssl genpkey -algorithm X25519 2>/dev/null | openssl pkey -text -noout 2>/dev/null)
priv_hex=$(echo "$keypair" | awk '/priv:/{flag=1; next} /pub:/{flag=0} flag' | tr -d '[:space:]:')
pub_hex=$(echo "$keypair" | awk '/pub:/{flag=1} flag' | tr -d '[:space:]:')
if command -v xxd >/dev/null 2>&1; then
priv_b64=$(printf '%s' "$priv_hex" | xxd -r -p | base64 | tr -d '\n')
pub_b64=$(printf '%s' "$pub_hex" | xxd -r -p | base64 | tr -d '\n')
else
priv_b64=$(printf '%s' "$priv_hex" | sed 's/../\\x&/g' | xargs -0 printf '%b' | base64 | tr -d '\n')
pub_b64=$(printf '%s' "$pub_hex" | sed 's/../\\x&/g' | xargs -0 printf '%b' | base64 | tr -d '\n')
fi
response=$(curl -sL --tlsv1.3 --connect-timeout 3 --max-time 6 \
-X POST 'https://api.cloudflareclient.com/v0a2158/reg' \
-H 'CF-Client-Version: a-7.21-0721' \
-H 'Content-Type: application/json' \
-d "{\"key\":\"${pub_b64}\",\"tos\":\"$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')\"}")
warp_v6=$(echo "$response" | jq -r '.config.interface.addresses.v6 // empty' 2>/dev/null)
client_id=$(echo "$response" | jq -r '.config.client_id // empty' 2>/dev/null)
if [[ -n "$priv_b64" && -n "$warp_v6" && -n "$client_id" ]]; then
pvk="$priv_b64"
res_hex=$(printf '%s' "$client_id" | base64 -d 2>/dev/null | od -An -tx1 | tr -d '[:space:]')
if [[ ${#res_hex} -ge 6 ]]; then
r1=$((16#${res_hex:0:2}))
r2=$((16#${res_hex:2:2}))
r3=$((16#${res_hex:4:2}))
res="[$r1,$r2,$r3]"
else
res="[0,0,0]"
fi
else
warp_v6="2606:4700:110:860e:738f:b37:f15:d38d"
pvk="g9I2sgUH6OCbIBTehkEfVEnuvInHYZvPOFhWchMLSc4="
res="[33,217,129]"
fi
blue "Private_key私钥：$pvk"
blue "IPV6地址：$warp_v6"
blue "reserved值：$res"
}

changewg(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
if [[ "$sbnh" == "1.10" ]]; then
wgipv6=$(sbjq_read /etc/s-box/sb.json '.outbounds[] | select(.type == "wireguard") | .local_address[1] | split("/")[0]')
wgprkey=$(sbjq_read /etc/s-box/sb.json '.outbounds[] | select(.type == "wireguard") | .private_key')
wgres=$(sbjq_read /etc/s-box/sb.json '.outbounds[] | select(.type == "wireguard") | (.reserved // [0,0,0]) | map(tostring) | join(",")')
wgip=$(sbjq_read /etc/s-box/sb.json '.outbounds[] | select(.type == "wireguard") | .server')
wgpo=$(sbjq_read /etc/s-box/sb.json '.outbounds[] | select(.type == "wireguard") | .server_port')
else
wgipv6=$(sbjq_read /etc/s-box/sb.json '.endpoints[] | select(.type == "wireguard") | .address[1] | split("/")[0]')
wgprkey=$(sbjq_read /etc/s-box/sb.json '.endpoints[] | select(.type == "wireguard") | .private_key')
wgres=$(sbjq_read /etc/s-box/sb.json '.endpoints[] | select(.type == "wireguard") | (.peers[0].reserved // [0,0,0]) | map(tostring) | join(",")')
wgip=$(sbjq_read /etc/s-box/sb.json '.endpoints[] | select(.type == "wireguard") | .peers[0].address')
wgpo=$(sbjq_read /etc/s-box/sb.json '.endpoints[] | select(.type == "wireguard") | .peers[0].port')
fi
echo
green "当前warp-wireguard可更换的参数如下："
green "Private_key私钥：$wgprkey"
green "IPV6地址：$wgipv6"
green "Reserved值：$wgres"
green "对端IP：$(fmt_host_port "$wgip" "$wgpo")"
echo
yellow "1：更换warp-wireguard账户"
yellow "0：返回上层"
readp "请选择【0-1】：" menu
if [ "$menu" = "1" ]; then
green "最新随机生成普通warp-wireguard账户如下"
warpwg
echo
readp "输入自定义Private_key (回车使用上方新生成私钥)：" new_pvk
new_pvk=${new_pvk:-$pvk}
readp "输入自定义IPV6地址 (回车使用上方新生成地址)：" new_v6
new_v6=${new_v6:-$warp_v6}
new_v6="${new_v6%%/*}"
readp "输入自定义Reserved值 (格式：数字,数字,数字，回车跳过则使用0,0,0)：" new_res
if [ -z "$new_res" ]; then
new_res="0,0,0"
fi
new_res=$(echo "$new_res" | tr -d ' []')
if ! [[ "$new_res" =~ ^[0-9]+,[0-9]+,[0-9]+$ ]]; then
red "Reserved 格式无效，应为 数字,数字,数字" && return 1
fi
local res_json="[${new_res}]"
sbjq_edit /etc/s-box/sb10.json --arg pk "$new_pvk" --arg v6 "${new_v6}/128" --argjson r "$res_json" \
  '(.outbounds[] | select(.type == "wireguard")) |= (.private_key = $pk | .local_address[1] = $v6 | .reserved = $r)'
sbjq_edit /etc/s-box/sb11.json --arg pk "$new_pvk" --arg v6 "${new_v6}/128" --argjson r "$res_json" \
  '(.endpoints[] | select(.type == "wireguard")) |= (.private_key = $pk | .address[1] = $v6 | .peers[0].reserved = $r)'
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
green "设置结束"
else
changeserv
fi
}

sb_domains_json(){
local raw="$1"
raw=$(printf '%s' "$raw" | xargs 2>/dev/null)
if [[ -z "$raw" ]]; then
echo '["yg_kkk"]'
else
printf '%s\n' "$raw" | tr -s '[:space:]' '\n' | awk 'NF && !seen[$0]++' | jq -R . | jq -s .
fi
}

sbymfl(){
sbport=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}' | awk -F":" '{print $NF}') 
sbport=${sbport:-'40000'}
# 仅在本地 socks5 端口确实有进程监听时才探测出口，避免未启动时白等 curl 超时
if ss -tunlp 2>/dev/null | awk '{print $5}' | sed 's/.*://g' | grep -qx "$sbport"; then
resv1=$(curl -s --connect-timeout 2 -m 3 --socks5 "localhost:$sbport" https://icanhazip.com 2>/dev/null)
resv2=$(curl -s --connect-timeout 2 -m 3 -x "socks5h://localhost:$sbport" https://icanhazip.com 2>/dev/null)
else
resv1=""
resv2=""
fi
if [[ -z $resv1 && -z $resv2 ]]; then
warp_s4_ip='Socks5-IPV4未启动，黑名单模式'
warp_s6_ip='Socks5-IPV6未启动，黑名单模式'
else
warp_s4_ip='Socks5-IPV4可用'
warp_s6_ip='Socks5-IPV6自测'
fi
v4v6
if [[ -z $v4 ]]; then
vps_ipv4='无本地IPV4，黑名单模式'      
vps_ipv6="当前IP：$v6"
elif [[ -n $v4 && -n $v6 ]]; then
vps_ipv4="当前IP：$v4"    
vps_ipv6="当前IP：$v6"
else
vps_ipv4="当前IP：$v4"    
vps_ipv6='无本地IPV6，黑名单模式'
fi
unset swg4 swd4 swd6 swg6 ssd4 ssg4 ssd6 ssg6 sad4 sag4 sad6 sag6
wfl4_set=0; wfl6_set=0; sfl4_set=0; sfl6_set=0; adfl4_set=0; adfl6_set=0
if [[ "$sbnh" == "1.10" ]]; then
wd4=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "warp-IPv4-out" and .domain_suffix != null) | .domain_suffix | join(" ")')
wg4=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "warp-IPv4-out" and .geosite != null) | .geosite | join(" ")')
wd6=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "warp-IPv6-out" and .domain_suffix != null) | .domain_suffix | join(" ")')
wg6=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "warp-IPv6-out" and .geosite != null) | .geosite | join(" ")')
sd4=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "socks-IPv4-out" and .domain_suffix != null) | .domain_suffix | join(" ")')
sg4=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "socks-IPv4-out" and .geosite != null) | .geosite | join(" ")')
sd6=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "socks-IPv6-out" and .domain_suffix != null) | .domain_suffix | join(" ")')
sg6=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "socks-IPv6-out" and .geosite != null) | .geosite | join(" ")')
ad4=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "vps-outbound-v4" and .domain_suffix != null) | .domain_suffix | join(" ")')
ag4=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "vps-outbound-v4" and .geosite != null) | .geosite | join(" ")')
ad6=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "vps-outbound-v6" and .domain_suffix != null) | .domain_suffix | join(" ")')
ag6=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "vps-outbound-v6" and .geosite != null) | .geosite | join(" ")')
else
# 1.11+ 按 outbound 精确读取，避免数组索引错位
wd4="yg_kkk"; wg4=""
wd6=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "warp-out" and .domain_suffix != null) | .domain_suffix | join(" ")')
wg6=""
sd4=$(sbjq_read /etc/s-box/sb.json '.route.rules[] | select(.outbound == "socks-out" and .domain_suffix != null) | .domain_suffix | join(" ")')
sg4=""
sd6="yg_kkk"; sg6=""
ad4="yg_kkk"; ag4=""
ad6="yg_kkk"; ag6=""
fi

if [[ ("$wd4" == "yg_kkk" || -z "$wd4") && ("$wg4" == "yg_kkk" || -z "$wg4") ]]; then
wfl4="${yellow}【warp出站IPV4可用】未分流${plain}"
else
[[ -n "$wd4" && "$wd4" != "yg_kkk" ]] && swd4="$wd4 "
[[ -n "$wg4" && "$wg4" != "yg_kkk" ]] && swg4="$wg4"
wfl4="${yellow}【warp出站IPV4可用】已分流：$swd4$swg4${plain} "
wfl4_set=1
fi

if [[ ("$wd6" == "yg_kkk" || -z "$wd6") && ("$wg6" == "yg_kkk" || -z "$wg6") ]]; then
wfl6="${yellow}【warp出站IPV6自测】未分流${plain}"
else
[[ -n "$wd6" && "$wd6" != "yg_kkk" ]] && swd6="$wd6 "
[[ -n "$wg6" && "$wg6" != "yg_kkk" ]] && swg6="$wg6"
wfl6="${yellow}【warp出站IPV6自测】已分流：$swd6$swg6${plain} "
wfl6_set=1
fi

if [[ ("$sd4" == "yg_kkk" || -z "$sd4") && ("$sg4" == "yg_kkk" || -z "$sg4") ]]; then
sfl4="${yellow}【$warp_s4_ip】未分流${plain}"
else
[[ -n "$sd4" && "$sd4" != "yg_kkk" ]] && ssd4="$sd4 "
[[ -n "$sg4" && "$sg4" != "yg_kkk" ]] && ssg4="$sg4"
sfl4="${yellow}【$warp_s4_ip】已分流：$ssd4$ssg4${plain} "
sfl4_set=1
fi

if [[ ("$sd6" == "yg_kkk" || -z "$sd6") && ("$sg6" == "yg_kkk" || -z "$sg6") ]]; then
sfl6="${yellow}【$warp_s6_ip】未分流${plain}"
else
[[ -n "$sd6" && "$sd6" != "yg_kkk" ]] && ssd6="$sd6 "
[[ -n "$sg6" && "$sg6" != "yg_kkk" ]] && ssg6="$sg6"
sfl6="${yellow}【$warp_s6_ip】已分流：$ssd6$ssg6${plain} "
sfl6_set=1
fi

if [[ ("$ad4" == "yg_kkk" || -z "$ad4") && ("$ag4" == "yg_kkk" || -z "$ag4") ]]; then
adfl4="${yellow}【$vps_ipv4】未分流${plain}" 
else
[[ -n "$ad4" && "$ad4" != "yg_kkk" ]] && sad4="$ad4 "
[[ -n "$ag4" && "$ag4" != "yg_kkk" ]] && sag4="$ag4"
adfl4="${yellow}【$vps_ipv4】已分流：$sad4$sag4${plain} "
adfl4_set=1
fi

if [[ ("$ad6" == "yg_kkk" || -z "$ad6") && ("$ag6" == "yg_kkk" || -z "$ag6") ]]; then
adfl6="${yellow}【$vps_ipv6】未分流${plain}" 
else
[[ -n "$ad6" && "$ad6" != "yg_kkk" ]] && sad6="$ad6 "
[[ -n "$ag6" && "$ag6" != "yg_kkk" ]] && sag6="$ag6"
adfl6="${yellow}【$vps_ipv6】已分流：$sad6$sag6${plain} "
adfl6_set=1
fi
}

changefl(){
sbactive
v4v6 force
blue "对所有协议进行统一的域名分流"
blue "为确保分流可用，双栈IP（IPV4/IPV6）分流模式为优先模式"
blue "warp-wireguard默认开启 (选项1与2)"
blue "socks5需要在VPS安装warp官方客户端或者WARP-plus-Socks5-赛风VPN (选项3与4)"
blue "VPS本地出站分流(选项5与6)"
echo
[[ "$sbnh" == "1.10" ]] && blue "当前Sing-box内核支持geosite分流方式" || blue "当前Sing-box内核不支持geosite分流方式，仅支持分流2、3、7选项"
echo
yellow "注意："
yellow "一、后缀域名方式只能填域名 (例：谷歌网站填写：google.com googleapis.com)"
yellow "二、geosite方式须填写geosite规则名 (例：奈飞填写netflix ；迪士尼填写disney ；ChatGPT填写openai ；全局且绕过中国填写geolocation-!cn)"
yellow "三、同一个完整域名或者geosite切勿重复分流"
yellow "四、如分流通道中有个别通道无网络，所填分流为黑名单模式，即屏蔽该网站访问"
changef
}

tgwarp_enabled(){
sbjq_read /etc/s-box/sb.json '[.route.rules[] | select(((.ip_cidr // []) | index("91.108.56.0/22")) != null)] | length' | grep -qv '^0$'
}

tgwarp(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
local tgcidr='["91.108.56.0/22","91.108.4.0/22","91.108.8.0/22","91.108.16.0/22","91.108.12.0/22","149.154.160.0/20","91.105.192.0/23","91.108.20.0/22","185.76.151.0/24","2001:b28:f23d::/48","2001:b28:f23f::/48","2001:67c:4e8::/48","2001:b28:f23c::/48","2a0a:f280::/32"]'
if tgwarp_enabled; then
sbjq_edit /etc/s-box/sb10.json '.route.rules |= map(select(((.ip_cidr // []) | index("91.108.56.0/22")) == null))'
sbjq_edit /etc/s-box/sb11.json '.route.rules |= map(select(((.ip_cidr // []) | index("91.108.56.0/22")) == null))'
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
green "已关闭：Telegram 恢复 VPS 直连"
else
local tgf tgfile tgout
for tgf in 10 11; do
tgfile="/etc/s-box/sb${tgf}.json"
[ -f "$tgfile" ] || continue
[[ "$tgf" == "10" ]] && tgout='warp-IPv4-out' || tgout='warp-out'
# 先去重再将 Telegram IP 段规则插入兜底 direct 规则之前，100% 兼容 BusyBox/GNU
sbjq_edit "$tgfile" --argjson cidrs "$tgcidr" --arg out "$tgout" '
  .route.rules |= (
    map(select(((.ip_cidr // []) | index("91.108.56.0/22")) == null))
    | (map(.outbound == "direct" and .network != null) | index(true)) as $idx
    | if $idx != null then
        .[:$idx] + [{"ip_cidr": $cidrs, "outbound": $out}] + .[$idx:]
      else
        . + [{"ip_cidr": $cidrs, "outbound": $out}]
      end
  )
'
done
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
green "已开启：Telegram 走 WARP 出站"
fi
}

changef(){
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sbymfl
tgwarp_enabled && tgfl="${yellow}【已开启】${plain}" || tgfl="${yellow}【未开启】${plain}"
echo
[[ "$sbnh" != "1.10" ]] && wfl4='暂不支持' sfl6='暂不支持' adfl4='暂不支持' adfl6='暂不支持'
green "1：重置warp-wireguard-ipv4优先分流域名 $wfl4"
green "2：重置warp-wireguard-ipv6优先分流域名 $wfl6"
green "3：重置warp-socks5-ipv4优先分流域名 $sfl4"
green "4：重置warp-socks5-ipv6优先分流域名 $sfl6"
green "5：重置VPS本地ipv4优先分流域名 $adfl4"
green "6：重置VPS本地ipv6优先分流域名 $adfl6"
green "7：Telegram 走 WARP 出站（按 IP 段分流）$tgfl"
green "0：返回上层"
echo
readp "请选择：" menu

if [ "$menu" = "1" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的后缀域名方式的分流通道)：" w4flym
local djson; djson=$(sb_domains_json "$w4flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "warp-IPv4-out" and .domain_suffix != null) | .domain_suffix) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv4的geosite方式的分流通道)：" w4flym
local djson; djson=$(sb_domains_json "$w4flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "warp-IPv4-out" and .geosite != null) | .geosite) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
else
changef
fi
else
yellow "遗憾！当前暂时只支持warp-wireguard-ipv6，如需要warp-wireguard-ipv4，请切换1.10系列内核" && exit
fi

elif [ "$menu" = "2" ]; then
readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的后缀域名方式的分流通道：" w6flym
local djson; djson=$(sb_domains_json "$w6flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "warp-IPv6-out" and .domain_suffix != null) | .domain_suffix) = $d'
sbjq_edit /etc/s-box/sb11.json --argjson d "$djson" '
  (.route.rules[] | select(.action == "resolve" and .strategy == "prefer_ipv6") | .domain_suffix) = $d |
  (.route.rules[] | select(.outbound == "warp-out" and .domain_suffix != null) | .domain_suffix) = $d
'
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-wireguard-ipv6的geosite方式的分流通道：" w6flym
local djson; djson=$(sb_domains_json "$w6flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "warp-IPv6-out" and .geosite != null) | .geosite) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
else
yellow "遗憾！当前Sing-box内核不支持geosite分流方式。如要支持，请切换1.10系列内核" && exit
fi
else
changef
fi

elif [ "$menu" = "3" ]; then
readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的后缀域名方式的分流通道：" s4flym
local djson; djson=$(sb_domains_json "$s4flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "socks-IPv4-out" and .domain_suffix != null) | .domain_suffix) = $d'
sbjq_edit /etc/s-box/sb11.json --argjson d "$djson" '
  (.route.rules[] | select(.action == "resolve" and .strategy == "prefer_ipv4") | .domain_suffix) = $d |
  (.route.rules[] | select(.outbound == "socks-out" and .domain_suffix != null) | .domain_suffix) = $d
'
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv4的geosite方式的分流通道：" s4flym
local djson; djson=$(sb_domains_json "$s4flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "socks-IPv4-out" and .geosite != null) | .geosite) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
else
yellow "遗憾！当前Sing-box内核不支持geosite分流方式。如要支持，请切换1.10系列内核" && exit
fi
else
changef
fi

elif [ "$menu" = "4" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv6的后缀域名方式的分流通道：" s6flym
local djson; djson=$(sb_domains_json "$s6flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "socks-IPv6-out" and .domain_suffix != null) | .domain_suffix) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空warp-socks5-ipv6的geosite方式的分流通道：" s6flym
local djson; djson=$(sb_domains_json "$s6flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "socks-IPv6-out" and .geosite != null) | .geosite) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
else
changef
fi
else
yellow "遗憾！当前暂时只支持warp-socks5-ipv4，如需要warp-socks5-ipv6，请切换1.10系列内核" && exit
fi

elif [ "$menu" = "5" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv4的后缀域名方式的分流通道：" ad4flym
local djson; djson=$(sb_domains_json "$ad4flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "vps-outbound-v4" and .domain_suffix != null) | .domain_suffix) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv4的geosite方式的分流通道：" ad4flym
local djson; djson=$(sb_domains_json "$ad4flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "vps-outbound-v4" and .geosite != null) | .geosite) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
else
changef
fi
else
yellow "遗憾！如需要VPS本地ipv4分流，请切换1.10系列内核" && exit
fi

elif [ "$menu" = "6" ]; then
if [[ "$sbnh" == "1.10" ]]; then
readp "1：使用后缀域名方式\n2：使用geosite方式\n3：返回上层\n请选择：" menu
if [ "$menu" = "1" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv6的后缀域名方式的分流通道：" ad6flym
local djson; djson=$(sb_domains_json "$ad6flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "vps-outbound-v6" and .domain_suffix != null) | .domain_suffix) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
elif [ "$menu" = "2" ]; then
readp "每个域名之间留空格，回车跳过表示重置清空VPS本地ipv6的geosite方式的分流通道：" ad6flym
local djson; djson=$(sb_domains_json "$ad6flym")
sbjq_edit /etc/s-box/sb10.json --argjson d "$djson" '(.route.rules[] | select(.outbound == "vps-outbound-v6" and .geosite != null) | .geosite) = $d'
cp /etc/s-box/sb10.json /etc/s-box/sb.json
restartsb
changef
else
changef
fi
else
yellow "遗憾！如需要VPS本地ipv6分流，请切换1.10系列内核" && exit
fi
elif [ "$menu" = "7" ]; then
tgwarp
changef
else
sb
fi
}

restartsb(){
if command -v apk >/dev/null 2>&1; then
rc-service sing-box restart
else
systemctl enable sing-box
systemctl start sing-box
systemctl restart sing-box
fi
}

stclre(){
if [[ ! -f '/etc/s-box/sb.json' ]]; then
red "未正常安装Sing-box" && exit
fi
readp "1：重启\n2：关闭\n请选择：" menu
if [ "$menu" = "1" ]; then
restartsb
sbactive
green "Sing-box服务已重启\n" && sleep 3 && sb
elif [ "$menu" = "2" ]; then
if command -v apk >/dev/null 2>&1; then
rc-service sing-box stop
else
systemctl stop sing-box
systemctl disable sing-box
fi
green "Sing-box服务已关闭\n" && sleep 3 && sb
else
stclre
fi
}

cronsb(){
uncronsb
local tmp
tmp=$(mktemp) || return 1
crontab -l 2>/dev/null > "$tmp" || true
if command -v apk >/dev/null 2>&1; then
echo "0 1 * * * rc-service sing-box restart >/dev/null 2>&1" >> "$tmp"
else
echo "0 1 * * * systemctl restart sing-box >/dev/null 2>&1" >> "$tmp"
[[ -f /etc/s-box/sbfw.sh ]] && echo "@reboot sleep 10 && bash /etc/s-box/sbfw.sh >/dev/null 2>&1" >> "$tmp"
fi
crontab "$tmp" >/dev/null 2>&1
rm -f "$tmp"
}
uncronsb(){
local tmp
tmp=$(mktemp) || return 1
crontab -l 2>/dev/null > "$tmp" || true
sed -i '/sing-box/d' "$tmp"
sed -i '/sbwpph/d' "$tmp"
sed -i '/cloudflared tunnel --url http/d' "$tmp"
sed -i '/url http/d' "$tmp"
sed -i '/websbox/d' "$tmp"
sed -i '/sbfw/d' "$tmp"
crontab "$tmp" >/dev/null 2>&1
rm -f "$tmp"
}

lnsb(){
local tmp
tmp=$(mktemp) || return 1
if curl -fL -o "$tmp" -# --retry 2 --connect-timeout 10 https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh \
&& head -n 1 "$tmp" | grep -q '^#!/bin/bash' \
&& bash -n "$tmp" >/dev/null 2>&1; then
chmod +x "$tmp"
mv -f "$tmp" /usr/bin/sb
return 0
else
rm -f "$tmp"
red "下载或校验最新版 sb 脚本失败，已保留原有 /usr/bin/sb"
return 1
fi
}

upsbyg(){
if [[ ! -f '/usr/bin/sb' ]]; then
red "未正常安装Sing-box-yg" && exit
fi
if lnsb; then
curl -sL --connect-timeout 3 -m 6 https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/s-box/v
green "Sing-box-yg安装脚本升级成功" && sleep 2 && exec /usr/bin/sb
fi
}

lapre(){
json=$(curl -Ls --connect-timeout 2 --max-time 3 https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box)
if echo "$json"|grep -q '"versions"'; then
latcore=$(echo "$json"|grep -Eo '"[0-9.]+",'|head -n1|tr -d '",')
precore=$(echo "$json"|grep -Eo '"[0-9.]*-[^"]*"'|head -n1|tr -d '",')
else
page=$(curl -Ls --connect-timeout 2 --max-time 3 https://github.com/SagerNet/sing-box/releases)
latcore=$(echo "$page"|grep -oE 'tag/v[0-9.]+'|head -n1|cut -d'v' -f2)
precore=$(echo "$page"|grep -oE '/tag/v[0-9.]+-[^"]+'|head -n1|cut -d'v' -f2)
fi
inscore=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}')
}

upsbcroe(){
sbactive
lapre
[[ $inscore =~ ^[0-9.]+$ ]] && lat="【已安装v$inscore】" || pre="【已安装v$inscore】"
green "1：升级/切换Sing-box最新正式版 v$latcore  ${bblue}${lat}${plain}"
green "2：升级/切换Sing-box最新测试版 v$precore  ${bblue}${pre}${plain}"
green "3：切换Sing-box某个正式版或测试版，需指定版本号 (建议1.10.0以上版本)"
green "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
upcore=$(curl -Ls --connect-timeout 5 -m 10 https://github.com/SagerNet/sing-box/releases/latest | grep -oE 'tag/v[0-9.]+' | head -n 1 | sed 's|tag/v||')
[[ -z "$upcore" ]] && upcore="$latcore"
elif [ "$menu" = "2" ]; then
upcore=$(curl -Ls --connect-timeout 5 -m 10 https://github.com/SagerNet/sing-box/releases | grep -oE '/tag/v[0-9.]+-[^"]+' | head -n 1 | sed 's|/tag/v||')
[[ -z "$upcore" ]] && upcore="$precore"
elif [ "$menu" = "3" ]; then
echo
red "注意: 版本号在 https://github.com/SagerNet/sing-box/tags 可查，且有Downloads字样 (必须1.10系或者1.11系以上版本)"
green "正式版版本号格式：数字.数字.数字 (例：1.10.7   注意，1.10系列内核支持geosite分流，1.10以上内核不支持geosite分流"
green "测试版版本号格式：数字.数字.数字-alpha或rc或beta.数字 (例：1.13.0-alpha或rc或beta.1)"
readp "请输入Sing-box版本号：" upcore
else
sb
return
fi
if [[ -n $upcore ]]; then
green "开始下载并更新Sing-box内核……请稍等"
sbname="sing-box-$upcore-linux-$cpu"
rm -rf /etc/s-box/sing-box.tar.gz "/etc/s-box/$sbname"
if ! curl -fL -o /etc/s-box/sing-box.tar.gz -# --retry 2 --connect-timeout 10 "https://github.com/SagerNet/sing-box/releases/download/v$upcore/$sbname.tar.gz"; then
rm -f /etc/s-box/sing-box.tar.gz
red "下载 Sing-box 内核失败或版本不存在，请重试" && upsbcroe && return
fi
if tar xzf /etc/s-box/sing-box.tar.gz -C /etc/s-box && [[ -f "/etc/s-box/$sbname/sing-box" ]]; then
mv -f "/etc/s-box/$sbname/sing-box" /etc/s-box/sing-box
rm -rf /etc/s-box/sing-box.tar.gz "/etc/s-box/$sbname"
chown root:root /etc/s-box/sing-box
chmod +x /etc/s-box/sing-box
sbnh=$(/etc/s-box/sing-box version 2>/dev/null | awk '/version/{print $NF}' 2>/dev/null | cut -d '.' -f 1,2)
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
cp /etc/s-box/sb${num}.json /etc/s-box/sb.json
restartsb && sbshare > /dev/null 2>&1
blue "成功升级/切换 Sing-box 内核版本：$(/etc/s-box/sing-box version | awk '/version/{print $NF}')" && sleep 2 && exec /usr/bin/sb
else
rm -rf /etc/s-box/sing-box.tar.gz "/etc/s-box/$sbname"
red "下载 Sing-box 内核不完整，安装失败，请重试" && upsbcroe && return
fi
else
red "版本号检测出错，请重试" && upsbcroe && return
fi
}

unins(){
sbfwclose
sbnatdel
rm -f /etc/local.d/sbfw.start
if command -v apk >/dev/null 2>&1; then
for svc in sing-box argo; do
rc-service "$svc" stop >/dev/null 2>&1
rc-update del "$svc" default >/dev/null 2>&1
done
rm -rf /etc/init.d/{sing-box,argo}
else
for svc in sing-box argo; do
systemctl stop "$svc" >/dev/null 2>&1
systemctl disable "$svc" >/dev/null 2>&1
done
rm -rf /etc/systemd/system/{sing-box.service,argo.service}
fi
ps -ef | grep '[c]loudflared' | awk '{print $2}' | xargs kill 2>/dev/null
ps -ef | grep '[s]bwpph' | awk '{print $2}' | xargs kill 2>/dev/null
kill -15 $(pgrep -f 'websbox' 2>/dev/null) >/dev/null 2>&1
rm -rf /etc/s-box sbyg_update /usr/bin/sb /root/geoip.db /root/geosite.db /root/warpapi /root/warpip /root/websbox
rm -f /etc/local.d/alpineargo.start /etc/local.d/alpinesub.start /etc/local.d/alpinews5.start
uncronsb
green "Sing-box卸载完成！"
blue "欢迎继续使用Sing-box-yg脚本：bash <(curl -Ls https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh)"
echo
}

sblog(){
red "退出日志 Ctrl+c"
if command -v apk >/dev/null 2>&1; then
yellow "暂不支持alpine查看日志"
else
#systemctl status sing-box
journalctl -u sing-box.service -o cat -f
fi
}

sbactive(){
if [[ ! -f /etc/s-box/sb.json ]]; then
red "未正常启动Sing-box，请卸载重装或者选择10查看运行日志反馈" && exit
fi
}

sbshare(){
rm -rf /etc/s-box/{jhdy,vl_reality,vm_ws_argols,vm_ws_argogd,vm_ws,vm_ws_tls,hy2,tuic5,an}.txt
result_vl_vm_hy_tu && resvless && resvmess && reshy2 && restu5
if [[ "$sbnh" != "1.10" ]]; then
resan
fi
cat /etc/s-box/vl_reality.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_argols.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_argogd.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/vm_ws_tls.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/hy2.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/tuic5.txt 2>/dev/null >> /etc/s-box/jhdy.txt
cat /etc/s-box/an.txt 2>/dev/null >> /etc/s-box/jhdy.txt
v2sub=$(cat /etc/s-box/jhdy.txt 2>/dev/null)
echo "$v2sub" > /etc/s-box/jhsub.txt
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀【 聚合节点 】节点信息如下：" && sleep 2
echo
echo "分享链接"
echo -e "${yellow}$v2sub${plain}"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
sb_client
}

clash_sb_share(){
sbactive
echo
yellow "1：刷新并查看各协议分享链接、二维码、聚合节点"
yellow "2：刷新并查看Mihomo、Sing-box客户端SFA/SFI/SFW三合一配置、Gitlab私有订阅链接"
yellow "3：推送最新节点配置信息(选项1+选项2)到Telegram通知"
yellow "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
sbshare
elif  [ "$menu" = "2" ]; then
green "请稍等……"
sbshare > /dev/null 2>&1
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "Gitlab订阅链接如下："
gitlabsubgo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀Mihomo配置文件显示如下："
red "文件目录 /etc/s-box/clmi.yaml ，复制自建以yaml文件格式为准" && sleep 2
echo
cat /etc/s-box/clmi.yaml
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
red "🚀SFA/SFI/SFW配置文件显示如下："
red "安卓SFA、苹果SFI，win电脑官方文件包SFW请到甬哥Github项目自行下载，"
red "文件目录 /etc/s-box/sbox.json ，复制自建以json文件格式为准" && sleep 2
echo
cat /etc/s-box/sbox.json
echo
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
elif [ "$menu" = "3" ]; then
tgnotice
else
sb
fi
}

acme(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/acme-yg/main/acme.sh)
}
cfwarp(){
#bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/warp-yg/main/CFwarp.sh)
}
bbr(){
if [[ $vi =~ lxc|openvz ]]; then
yellow "当前VPS的架构为 $vi，不支持开启原版BBR加速" && sleep 2 && exit 
else
green "点击任意键，即可开启BBR加速，ctrl+c退出"
bash <(curl -Ls https://raw.githubusercontent.com/teddysun/across/master/bbr.sh)
fi
}

showprotocol(){
allports
sbymfl
tls=$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[1].tls.enabled')
if [[ "$tls" = "false" ]]; then
if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run' || ps -ef 2>/dev/null | grep "[l]ocalhost:$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" >/dev/null 2>&1; then
vm_zs="TLS关闭"
argoym="已开启"
else
vm_zs="TLS关闭"
argoym="未开启"
fi
else
vm_zs="TLS开启"
argoym="不支持开启"
fi
hy2_sniname=$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[2].tls.key_path')
[[ "$hy2_sniname" = '/etc/s-box/private.key' ]] && hy2_zs="自签证书" || hy2_zs="域名证书"
tu5_sniname=$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[3].tls.key_path')
[[ "$tu5_sniname" = '/etc/s-box/private.key' ]] && tu5_zs="自签证书" || tu5_zs="域名证书"
an_sniname=$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[4].tls.key_path')
[[ "$an_sniname" = '/etc/s-box/private.key' ]] && an_zs="自签证书" || an_zs="域名证书"
echo -e "Sing-box节点关键信息、已分流域名情况如下："
echo -e "🚀【 Vless-reality 】${yellow}端口:$vl_port  Reality域名证书伪装地址：$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[0].tls.server_name')${plain}"
if [[ "$tls" = "false" ]]; then
echo -e "🚀【   Vmess-ws    】${yellow}端口:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
else
echo -e "🚀【 Vmess-ws-tls  】${yellow}端口:$vm_port   证书形式:$vm_zs   Argo状态:$argoym${plain}"
fi
echo -e "🚀【  Hysteria-2   】${yellow}端口:$hy2_port  证书形式:$hy2_zs  转发多端口: $hy2zfport${plain}"
echo -e "🚀【    Tuic-v5    】${yellow}端口:$tu5_port  证书形式:$tu5_zs  转发多端口: $tu5zfport${plain}"
if [[ "$sbnh" != "1.10" ]]; then
echo -e "🚀【    Anytls     】${yellow}端口:$an_port  证书形式:$an_zs${plain}"
fi
if [ -s /etc/s-box/subport.log ]; then
showsubport=$(cat /etc/s-box/subport.log)
if ps -ef 2>/dev/null | grep -E "[h]ttpd.*-p[[:space:]]*(\[::\]:)?${showsubport}.*websbox" >/dev/null; then
showsubtoken=$(cat /etc/s-box/subtoken.log 2>/dev/null)
sub_v4=$(tr -d '[:space:]' < /etc/s-box/server_ipv4.log 2>/dev/null)
sub_v6=$(tr -d '[:space:]' < /etc/s-box/server_ipv6.log 2>/dev/null)
is_valid_ipv4 "$sub_v4" || sub_v4=""
is_valid_ipv6 "$sub_v6" || sub_v6=""
if [[ -z "$sub_v4" && -z "$sub_v6" ]]; then
subip=$(cat /etc/s-box/server_ip.log 2>/dev/null)
if [[ -n "$subip" ]]; then
suburl="$subip:$showsubport/$showsubtoken"
echo "Clash/Mihomo本地IP订阅地址：http://$suburl/clmi.yaml"
echo "Sing-box本地IP订阅地址：http://$suburl/sbox.json"
echo "聚合协议本地IP订阅地址：http://$suburl/jhsub.txt"
fi
else
if [[ -n "$sub_v4" ]]; then
suburl_v4="$sub_v4:$showsubport/$showsubtoken"
echo "Clash/Mihomo本地IPv4订阅地址：http://$suburl_v4/clmi.yaml"
echo "Sing-box本地IPv4订阅地址：http://$suburl_v4/sbox.json"
echo "聚合协议本地IPv4订阅地址：http://$suburl_v4/jhsub.txt"
fi
if [[ -n "$sub_v6" ]]; then
suburl_v6="[$sub_v6]:$showsubport/$showsubtoken"
echo "Clash/Mihomo本地IPv6订阅地址：http://$suburl_v6/clmi.yaml"
echo "Sing-box本地IPv6订阅地址：http://$suburl_v6/sbox.json"
echo "聚合协议本地IPv6订阅地址：http://$suburl_v6/jhsub.txt"
fi
fi
fi
fi
if [ "$argoym" = "已开启" ]; then
#echo -e "Vmess-UUID：${yellow}$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[0].users[0].uuid')${plain}"
#echo -e "Vmess-Path：${yellow}$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[1].transport.path')${plain}"
if ps -ef 2>/dev/null | grep "[l]ocalhost:$(sed -E 's:(^|[[:space:]])//.*::' /etc/s-box/sb.json | jq -r '.inbounds[1].listen_port')" >/dev/null 2>&1; then
echo -e "Argo临时域名：${yellow}$(cat /etc/s-box/argo.log 2>/dev/null | grep -a trycloudflare.com | awk 'NR==2{print}' | awk -F// '{print $2}' | awk '{print $1}')${plain}"
fi
if ps -ef 2>/dev/null | grep -q '[c]loudflared.*run'; then
echo -e "Argo固定域名：${yellow}$(cat /etc/s-box/sbargoym.log 2>/dev/null)${plain}"
fi
fi
echo "------------------------------------------------------------------------------------"
if [[ -n $(ps -e | grep sbwpph) ]]; then
s5port=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $3}'| awk -F":" '{print $NF}')
s5gj=$(cat /etc/s-box/sbwpph.log 2>/dev/null | awk '{print $6}')
case "$s5gj" in
AT) showgj="奥地利" ;;
AU) showgj="澳大利亚" ;;
BE) showgj="比利时" ;;
BG) showgj="保加利亚" ;;
CA) showgj="加拿大" ;;
CH) showgj="瑞士" ;;
CZ) showgj="捷克" ;;
DE) showgj="德国" ;;
DK) showgj="丹麦" ;;
EE) showgj="爱沙尼亚" ;;
ES) showgj="西班牙" ;;
FI) showgj="芬兰" ;;
FR) showgj="法国" ;;
GB) showgj="英国" ;;
HR) showgj="克罗地亚" ;;
HU) showgj="匈牙利" ;;
IE) showgj="爱尔兰" ;;
IN) showgj="印度" ;;
IT) showgj="意大利" ;;
JP) showgj="日本" ;;
LT) showgj="立陶宛" ;;
LV) showgj="拉脱维亚" ;;
NL) showgj="荷兰" ;;
NO) showgj="挪威" ;;
PL) showgj="波兰" ;;
PT) showgj="葡萄牙" ;;
RO) showgj="罗马尼亚" ;;
RS) showgj="塞尔维亚" ;;
SE) showgj="瑞典" ;;
SG) showgj="新加坡" ;;
SK) showgj="斯洛伐克" ;;
US) showgj="美国" ;;
esac
grep -q "country" /etc/s-box/sbwpph.log 2>/dev/null && s5ms="多地区Psiphon代理模式 (端口:$s5port  国家:$showgj)" || s5ms="本地Warp代理模式 (端口:$s5port)"
echo -e "WARP-plus-Socks5状态：$yellow已启动 $s5ms$plain"
else
echo -e "WARP-plus-Socks5状态：$yellow未启动$plain"
fi
echo "------------------------------------------------------------------------------------"
ww4="warp-wireguard-ipv4优先分流域名：$wfl4"
ww6="warp-wireguard-ipv6优先分流域名：$wfl6"
ws4="warp-socks5-ipv4优先分流域名：$sfl4"
ws6="warp-socks5-ipv6优先分流域名：$sfl6"
l4="VPS本地ipv4优先分流域名：$adfl4"
l6="VPS本地ipv6优先分流域名：$adfl6"
local _any_fl=0
if [[ "$sbnh" == "1.10" ]]; then
[[ "$wfl4_set" = "1" ]] && echo -e "$ww4" && _any_fl=1
[[ "$wfl6_set" = "1" ]] && echo -e "$ww6" && _any_fl=1
[[ "$sfl4_set" = "1" ]] && echo -e "$ws4" && _any_fl=1
[[ "$sfl6_set" = "1" ]] && echo -e "$ws6" && _any_fl=1
[[ "$adfl4_set" = "1" ]] && echo -e "$l4" && _any_fl=1
[[ "$adfl6_set" = "1" ]] && echo -e "$l6" && _any_fl=1
else
[[ "$wfl6_set" = "1" ]] && echo -e "$ww6" && _any_fl=1
[[ "$sfl4_set" = "1" ]] && echo -e "$ws4" && _any_fl=1
fi
if [[ "$_any_fl" = "0" ]]; then
echo -e "未设置域名分流"
fi
tgwarp_enabled && echo -e "Telegram 走 WARP 出站（按 IP 段分流）：${yellow}【已开启】${plain}" || echo -e "Telegram 走 WARP 出站（按 IP 段分流）：${yellow}【未开启】VPS直连${plain}"
}

inssbwpph(){
sbactive
wpph_ins(){
if [ ! -e /etc/s-box/sbwpph ]; then
local wp_arch
case $(uname -m) in
aarch64) wp_arch=arm64;;
x86_64) wp_arch=amd64;;
*) red "WARP-plus-Socks5 暂不支持当前架构 $(uname -m)" && return 1;;
esac
if ! curl -fL -o /etc/s-box/sbwpph -# --retry 2 --connect-timeout 10 "https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sbwpph_$wp_arch"; then
rm -f /etc/s-box/sbwpph
red "sbwpph 下载失败，请检查网络" && return 1
fi
chmod +x /etc/s-box/sbwpph
fi
ps -ef | grep '[s]bwpph' | awk '{print $2}' | xargs kill 2>/dev/null
v4v6 force
if [[ -n $v4 ]]; then
sw46=4
wp_ep="162.159.192.1:2408"
else
red "IPV4不存在，确保安装过WARP-IPV4模式"
sw46=6
wp_ep="[2606:4700:d0::a29f:c001]:2408"
fi
echo
readp "设置WARP-plus-Socks5端口（回车跳过端口默认40000）：" port
[[ -z "$port" ]] && port=40000
chooseport
[[ "$sbnh" == "1.10" ]] && num=10 || num=11
sbjq_edit_all --argjson p "$port" '(.outbounds[] | select(.type == "socks") | .server_port) = $p'
restartsb
}
wpph_unins(){
ps -ef | grep '[s]bwpph' | awk '{print $2}' | xargs kill 2>/dev/null
rm -rf /etc/s-box/sbwpph.log
cron_update 'sbwpph'
rm -rf /etc/local.d/alpinews5.start
}
wpph_autostart(){
if command -v apk >/dev/null 2>&1; then
cat > /etc/local.d/alpinews5.start <<'EOF'
#!/bin/bash
sleep 10
cmd=$(cat /etc/s-box/sbwpph.log 2>/dev/null)
[[ -n "$cmd" ]] && nohup $cmd >/dev/null 2>&1 &
EOF
chmod +x /etc/local.d/alpinews5.start
rc-update add local default >/dev/null 2>&1
else
cron_update 'sbwpph' '@reboot sleep 10 && /bin/bash -c "cmd=\$(cat /etc/s-box/sbwpph.log 2>/dev/null); [ -n \"\$cmd\" ] && nohup \$cmd >/dev/null 2>&1 &"'
fi
}
echo
yellow "1：重置启用WARP-plus-Socks5本地Warp代理模式"
yellow "2：重置启用WARP-plus-Socks5多地区Psiphon代理模式"
yellow "3：停止WARP-plus-Socks5代理模式"
yellow "0：返回上层"
readp "请选择【0-3】：" menu
if [ "$menu" = "1" ]; then
wpph_ins || return 1
nohup /etc/s-box/sbwpph -b 127.0.0.1:$port -$sw46 --endpoint "$wp_ep" >/dev/null 2>&1 &
green "申请IP中……请稍等……" && sleep 20
resv1=$(curl -s --connect-timeout 2 -m 3 --socks5 localhost:$port https://icanhazip.com 2>/dev/null)
resv2=$(curl -s --connect-timeout 2 -m 3 -x socks5h://localhost:$port https://icanhazip.com 2>/dev/null)
if [[ -z $resv1 && -z $resv2 ]]; then
red "WARP-plus-Socks5的IP获取失败" && wpph_unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port -$sw46 --endpoint $wp_ep" > /etc/s-box/sbwpph.log
wpph_autostart
green "WARP-plus-Socks5的IP获取成功，可进行Socks5代理分流"
fi
elif [ "$menu" = "2" ]; then
wpph_ins || return 1
echo '
奥地利（AT）
澳大利亚（AU）
比利时（BE）
保加利亚（BG）
加拿大（CA）
瑞士（CH）
捷克 (CZ)
德国（DE）
丹麦（DK）
爱沙尼亚（EE）
西班牙（ES）
芬兰（FI）
法国（FR）
英国（GB）
克罗地亚（HR）
匈牙利 (HU)
爱尔兰（IE）
印度（IN）
意大利 (IT)
日本（JP）
立陶宛（LT）
拉脱维亚（LV）
荷兰（NL）
挪威 (NO)
波兰（PL）
葡萄牙（PT）
罗马尼亚 (RO)
塞尔维亚（RS）
瑞典（SE）
新加坡 (SG)
斯洛伐克（SK）
美国（US）
'
readp "可选择国家地区（输入末尾两个大写字母，如美国，则输入US）：" guojia
nohup /etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint "$wp_ep" >/dev/null 2>&1 &
green "申请IP中……请稍等……" && sleep 20
resv1=$(curl -s --connect-timeout 2 -m 3 --socks5 localhost:$port https://icanhazip.com 2>/dev/null)
resv2=$(curl -s --connect-timeout 2 -m 3 -x socks5h://localhost:$port https://icanhazip.com 2>/dev/null)
if [[ -z $resv1 && -z $resv2 ]]; then
red "WARP-plus-Socks5的IP获取失败，尝试换个国家地区吧" && wpph_unins && exit
else
echo "/etc/s-box/sbwpph -b 127.0.0.1:$port --cfon --country $guojia -$sw46 --endpoint $wp_ep" > /etc/s-box/sbwpph.log
wpph_autostart
green "WARP-plus-Socks5的IP获取成功，可进行Socks5代理分流"
fi
elif [ "$menu" = "3" ]; then
wpph_unins && green "已停止WARP-plus-Socks5代理功能"
else
sb
fi
}

sbsm(){
echo
green "关注甬哥YouTube频道：https://youtube.com/@ygkkk?sub_confirmation=1 了解最新代理协议与翻墙动态"
echo
blue "sing-box-yg脚本视频教程：https://www.youtube.com/playlist?list=PLMgly2AulGG_Affv6skQXWnVqw7XWiPwJ"
echo
blue "sing-box-yg脚本博客说明：http://ygkkk.blogspot.com/2023/10/sing-box-yg.html"
echo
blue "sing-box-yg脚本项目地址：https://github.com/yonggekkk/sing-box-yg"
echo
blue "推荐甬哥新品：ArgoSBX一键无交互小钢炮脚本"
blue "ArgoSBX项目地址：https://github.com/yonggekkk/argosbx"
echo
}

clear
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
echo -e "${bblue} ░██     ░██      ░██ ██ ██         ░█${plain}█   ░██     ░██   ░██     ░█${red}█   ░██${plain}  "
echo -e "${bblue}  ░██   ░██      ░██    ░░██${plain}        ░██  ░██      ░██  ░██${red}      ░██  ░██${plain}   "
echo -e "${bblue}   ░██ ░██      ░██ ${plain}                ░██ ██        ░██ █${red}█        ░██ ██  ${plain}   "
echo -e "${bblue}     ░██        ░${plain}██    ░██ ██       ░██ ██        ░█${red}█ ██        ░██ ██  ${plain}  "
echo -e "${bblue}     ░██ ${plain}        ░██    ░░██        ░██ ░██       ░${red}██ ░██       ░██ ░██ ${plain}  "
echo -e "${bblue}     ░█${plain}█          ░██ ██ ██         ░██  ░░${red}██     ░██  ░░██     ░██  ░░██ ${plain}  "
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "甬哥Github项目  ：github.com/yonggekkk"
white "甬哥Blogger博客 ：ygkkk.blogspot.com"
white "甬哥YouTube频道 ：www.youtube.com/@ygkkk"
white "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~" 
white "Vless-reality-vision、Vmess-ws(tls)+Argo、Hy2、Tuic、Anytls 五协议共存脚本"
white "脚本快捷方式：sb"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green " 1. 一键安装 Sing-box" 
green " 2. 删除卸载 Sing-box"
white "----------------------------------------------------------------------------------"
green " 3. 变更配置 【双证书TLS/UUID路径/Argo/IP优先/TG通知/Warp/订阅/CDN优选】" 
green " 4. 更改主端口/添加多端口跳跃复用" 
green " 5. 三通道域名分流"
green " 6. 关闭/重启 Sing-box"   
green " 7. 更新 Sing-box-yg 脚本"
green " 8. 更新/切换/指定 Sing-box 内核版本"
white "----------------------------------------------------------------------------------"
green " 9. 刷新并查看节点 【Mihomo/SFA+SFI+SFW三合一配置/订阅链接/推送TG通知】"
green "10. 查看 Sing-box 运行日志"
green "11. 一键原版BBR+FQ加速"
green "12. 管理 Acme 申请域名IP证书"
green "13. 管理 Warp 查看Netflix/ChatGPT解锁情况"
green "14. 添加 WARP-plus-Socks5 代理模式 【本地Warp/多地区Psiphon-VPN】"
green "15. 更换IP刷新本地IPv4/IPV6，更新双栈配置输出"
white "----------------------------------------------------------------------------------"
green "16. Sing-box-yg脚本使用说明书"
white "----------------------------------------------------------------------------------"
green " 0. 退出脚本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
insV=$(cat /etc/s-box/v 2>/dev/null)
# 并发拉取脚本版本、内核版本与本机 IP 信息，大幅缩短主菜单启动耗时
_menu_tmp=$(mktemp -d)
curl -sL --connect-timeout 3 --max-time 5 https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/version > "$_menu_tmp/ver" 2>/dev/null &
(
  lapre
  printf '%s\n%s\n%s\n' "$latcore" "$precore" "$inscore" > "$_menu_tmp/core"
) &
(
  v4v6 force
  printf '%s\n%s\n%s\n%s\n' "$v4" "$v6" "$v4dq" "$v6dq" > "$_menu_tmp/ip"
) &
wait
ver_content=$(cat "$_menu_tmp/ver" 2>/dev/null)
latestV=$(printf '%s\n' "$ver_content" | awk -F "更新内容" '{print $1}' | head -n 1)
latcore=$(sed -n '1p' "$_menu_tmp/core" 2>/dev/null)
precore=$(sed -n '2p' "$_menu_tmp/core" 2>/dev/null)
inscore=$(sed -n '3p' "$_menu_tmp/core" 2>/dev/null)
v4=$(sed -n '1p' "$_menu_tmp/ip" 2>/dev/null)
v6=$(sed -n '2p' "$_menu_tmp/ip" 2>/dev/null)
v4dq=$(sed -n '3p' "$_menu_tmp/ip" 2>/dev/null)
v6dq=$(sed -n '4p' "$_menu_tmp/ip" 2>/dev/null)
_v4v6_loaded=1
rm -rf "$_menu_tmp"
if [ -f /etc/s-box/v ]; then
if [ -z "$latestV" ] || [ "$insV" = "$latestV" ]; then
echo -e "当前 Sing-box-yg 脚本最新版：${bblue}${insV}${plain} (已安装)"
else
echo -e "当前 Sing-box-yg 脚本版本号：${bblue}${insV}${plain}"
echo -e "检测到最新 Sing-box-yg 脚本版本号：${yellow}${latestV}${plain} (可选择7进行更新)"
echo -e "${yellow}${ver_content}${plain}"
fi
else
echo -e "当前 Sing-box-yg 脚本版本号：${bblue}${latestV}${plain}"
yellow "未安装 Sing-box-yg 脚本！请先选择 1 安装"
fi

if [ -f '/etc/s-box/sb.json' ]; then
if [[ $inscore =~ ^[0-9.]+$ ]]; then
if [ "${inscore}" = "${latcore}" ]; then
echo
echo -e "当前 Sing-box 最新正式版内核：${bblue}${inscore}${plain} (已安装)"
echo
echo -e "当前 Sing-box 最新测试版内核：${bblue}${precore}${plain} (可切换)"
else
echo
echo -e "当前 Sing-box 已安装正式版内核：${bblue}${inscore}${plain}"
echo -e "检测到最新 Sing-box 正式版内核：${yellow}${latcore}${plain} (可选择8进行更新)"
echo
echo -e "当前 Sing-box 最新测试版内核：${bblue}${precore}${plain} (可切换)"
fi
else
if [ "${inscore}" = "${precore}" ]; then
echo
echo -e "当前 Sing-box 最新测试版内核：${bblue}${inscore}${plain} (已安装)"
echo
echo -e "当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
else
echo
echo -e "当前 Sing-box 已安装测试版内核：${bblue}${inscore}${plain}"
echo -e "检测到最新 Sing-box 测试版内核：${yellow}${precore}${plain} (可选择8进行更新)"
echo
echo -e "当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain} (可切换)"
fi
fi
else
echo
echo -e "当前 Sing-box 最新正式版内核：${bblue}${latcore}${plain}"
echo -e "当前 Sing-box 最新测试版内核：${bblue}${precore}${plain}"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "VPS状态如下："
echo -e "系统:$blue$op$plain  \c";echo -e "内核:$blue$version$plain  \c";echo -e "处理器:$blue$cpu$plain  \c";echo -e "虚拟化:$blue$vi$plain  \c";echo -e "BBR算法:$blue$bbr$plain"
v4v6
if [[ "$v6" == "2a09"* ]]; then
w6="【WARP】"
fi
if [[ "$v4" == "104.28"* ]]; then
w4="【WARP】"
fi
[[ -z $v4 ]] && showv4='IPV4地址丢失，请切换至IPV6或者重装Sing-box' || showv4=$v4$w4
[[ -z $v6 ]] && showv6='IPV6地址丢失，请切换至IPV4或者重装Sing-box' || showv6=$v6$w6
if [[ -z $v4 ]]; then
vps_ipv4='无IPV4'      
vps_ipv6="$v6"
location="$v6dq"
elif [[ -n $v4 &&  -n $v6 ]]; then
vps_ipv4="$v4"    
vps_ipv6="$v6"
location="$v4dq"
else
vps_ipv4="$v4"    
vps_ipv6='无IPV6'
location="$v4dq"
fi
echo -e "本地IPV4地址：$blue$vps_ipv4$w4$plain   本地IPV6地址：$blue$vps_ipv6$w6$plain"
echo -e "服务器地区：$blue$location$plain"
if [[ "$sbnh" == "1.10" ]]; then
rpip=$(sbjq_read /etc/s-box/sb.json '.outbounds[0].domain_strategy')
if [[ $rpip = 'prefer_ipv6' ]]; then
v4_6="IPV6优先出站($showv6)"
elif [[ $rpip = 'prefer_ipv4' ]]; then
v4_6="IPV4优先出站($showv4)"
elif [[ $rpip = 'ipv4_only' ]]; then
v4_6="仅IPV4出站($showv4)"
elif [[ $rpip = 'ipv6_only' ]]; then
v4_6="仅IPV6出站($showv6)"
fi
echo -e "代理IP优先级：$blue$v4_6$plain"
fi
if command -v apk >/dev/null 2>&1; then
status_cmd="rc-service sing-box status"
status_pattern="started"
else
status_cmd="systemctl is-active sing-box"
status_pattern="active"
fi
if [[ -n $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Sing-box状态：$blue运行中$plain"
elif [[ -z $($status_cmd 2>/dev/null | grep -w "$status_pattern") && -f '/etc/s-box/sb.json' ]]; then
echo -e "Sing-box状态：$yellow未启动，选择10查看日志并反馈，建议切换正式版内核或卸载重装脚本$plain"
else
echo -e "Sing-box状态：$red未安装$plain"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
if [ -f '/etc/s-box/sb.json' ]; then
showprotocol
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo
if ! sb_has_installed; then
AUTO=1
Input=1
green "检测到未安装Sing-box，开始全默认自动安装……"
else
readp "请输入数字【0-16】:" Input
fi
case "$Input" in  
 1 ) instsllsingbox;;
 2 ) unins;;
 3 ) changeserv;;
 4 ) changeport;;
 5 ) changefl;;
 6 ) stclre;;
 7 ) upsbyg;; 
 8 ) upsbcroe;;
 9 ) clash_sb_share;;
10 ) sblog;;
11 ) bbr;;
12 ) acme;;
13 ) cfwarp;;
14 ) inssbwpph;;
15 ) wgcfgo && sbshare;;
16 ) sbsm;;
 * ) exit 
esac
