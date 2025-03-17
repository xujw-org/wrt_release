#!/usr/bin/env bash

# 设置脚本在遇到错误时立即退出
set -e
set -o errexit
set -o errtrace

# 定义错误处理函数，显示错误发生的行号和命令
error_handler() {
    echo "Error occurred in script at line: ${BASH_LINENO[0]}, command: '${BASH_COMMAND}'"
}

# 设置trap捕获ERR信号，当脚本执行出错时调用error_handler函数
trap 'error_handler' ERR

# 加载系统环境变量
source /etc/profile
# 获取脚本所在的绝对路径
BASE_PATH=$(cd $(dirname $0) && pwd)

# 从命令行参数获取仓库信息
REPO_URL=$1      # 仓库URL
REPO_BRANCH=$2   # 仓库分支
BUILD_DIR=$3     # 构建目录
COMMIT_HASH=$4   # 提交哈希值

# 设置全局变量
FEEDS_CONF="feeds.conf.default"  # feeds配置文件名
GOLANG_REPO="https://github.com/sbwml/packages_lang_golang"  # golang仓库地址
GOLANG_BRANCH="24.x"  # golang分支
THEME_SET="argon"     # 默认主题
LAN_ADDR="10.1.1.2"   # 默认LAN地址

# 克隆仓库函数：如果构建目录不存在，则克隆指定的仓库
clone_repo() {
    if [[ ! -d $BUILD_DIR ]]; then
        echo $REPO_URL $REPO_BRANCH
        git clone --depth 1 -b $REPO_BRANCH $REPO_URL $BUILD_DIR
    fi
}

# 清理构建环境：删除旧的配置文件和临时目录
clean_up() {
    cd $BUILD_DIR
    if [[ -f $BUILD_DIR/.config ]]; then
        \rm -f $BUILD_DIR/.config
    fi
    if [[ -d $BUILD_DIR/tmp ]]; then
        \rm -rf $BUILD_DIR/tmp
    fi
    if [[ -d $BUILD_DIR/logs ]]; then
        \rm -rf $BUILD_DIR/logs/*
    fi
    mkdir -p $BUILD_DIR/tmp
    echo "1" >$BUILD_DIR/tmp/.build
}

# 重置feeds配置：重置git仓库并更新到最新状态
reset_feeds_conf() {
    git reset --hard origin/$REPO_BRANCH
    git clean -f -d
    git pull
    if [[ $COMMIT_HASH != "none" ]]; then
        git checkout $COMMIT_HASH
    fi
}

# 更新feeds配置：删除注释行，添加small-package源，创建bpf.mk文件
update_feeds() {
    # 删除注释行
    sed -i '/^#/d' "$BUILD_DIR/$FEEDS_CONF"

    # 检查并添加 small-package 源
    if ! grep -q "small-package" "$BUILD_DIR/$FEEDS_CONF"; then
        # 确保文件以换行符结尾
        [ -z "$(tail -c 1 "$BUILD_DIR/$FEEDS_CONF")" ] || echo "" >>"$BUILD_DIR/$FEEDS_CONF"
        echo "src-git small8 https://github.com/kenzok8/small-package" >>"$BUILD_DIR/$FEEDS_CONF"
    fi

    # 添加bpf.mk解决更新报错
    if [ ! -f "$BUILD_DIR/include/bpf.mk" ]; then
        touch "$BUILD_DIR/include/bpf.mk"
    fi

    # 切换nss-packages源（已注释）
    #if grep -q "nss_packages" "$BUILD_DIR/$FEEDS_CONF"; then
    #    sed -i '/nss_packages/d' "$BUILD_DIR/$FEEDS_CONF"
    #    echo "src-git nss_packages https://github.com/ZqinKing/nss-packages.git" >>"$BUILD_DIR/$FEEDS_CONF"
    #fi

    # 更新 feeds
    ./scripts/feeds clean
    ./scripts/feeds update -a
}

# 移除不需要的包：清理冗余或冲突的软件包
remove_unwanted_packages() {
    # 定义要移除的LuCI应用列表
    local luci_packages=(
        "luci-app-passwall" "luci-app-smartdns" "luci-app-ddns-go" "luci-app-rclone"
        "luci-app-ssr-plus" "luci-app-vssr" "luci-theme-argon" "luci-app-daed" "luci-app-dae"
        "luci-app-alist" "luci-app-argon-config" "luci-app-homeproxy" "luci-app-haproxy-tcp"
        "luci-app-openclash" "luci-app-mihomo" "luci-app-appfilter"
    )
    # 定义要移除的网络包列表
    local packages_net=(
        "haproxy" "xray-core" "xray-plugin" "dns2socks" "alist" "hysteria"
        "smartdns" "mosdns" "adguardhome" "ddns-go" "naiveproxy" "shadowsocks-rust"
        "sing-box" "v2ray-core" "v2ray-geodata" "v2ray-plugin" "tuic-client"
        "chinadns-ng" "ipt2socks" "tcping" "trojan-plus" "simple-obfs"
        "shadowsocksr-libev" "dae" "daed" "mihomo" "geoview" "tailscale" "open-app-filter"
    )
    # 定义要从small8源移除的包列表
    local small8_packages=(
        "ppp" "firewall" "dae" "daed" "daed-next" "libnftnl" "nftables" "dnsmasq"
    )

    # 移除LuCI应用
    for pkg in "${luci_packages[@]}"; do
        \rm -rf ./feeds/luci/applications/$pkg
        \rm -rf ./feeds/luci/themes/$pkg
    done

    # 移除网络包
    for pkg in "${packages_net[@]}"; do
        \rm -rf ./feeds/packages/net/$pkg
    done

    # 移除small8包
    for pkg in "${small8_packages[@]}"; do
        \rm -rf ./feeds/small8/$pkg
    done

    # 移除istore包（如果存在）
    if [[ -d ./package/istore ]]; then
        \rm -rf ./package/istore
    fi

    # 清理qualcommax平台的uci-defaults脚本
    if [ -d "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults" ]; then
        find "$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults/" -type f -name "99*.sh" -exec rm -f {} +
    fi
}

# 更新默认主机名：修改系统默认主机名
update_default_hostname() {
    local hostname="ImmortalWrt"
    local file="$BUILD_DIR/package/base-files/files/bin/config_generate"
    
    if [ -f "$file" ]; then
        # 修改默认主机名
        sed -i "s/hostname='OpenWrt'/hostname='$hostname'/g" "$file"
    fi
}

# 添加网络设置脚本：提供一键修改网络配置的功能
add_network_config_script() {
    local script_path="$BUILD_DIR/package/base-files/files/usr/bin/network-config"
    
    # 确保目录存在
    mkdir -p "$(dirname "$script_path")"
    
    # 创建网络配置脚本
    cat <<'EOF' >"$script_path"
#!/bin/sh

# 网络配置脚本
# 用法: network-config [选项]
# 选项:
#   -h, --help              显示帮助信息
#   -i, --interface <接口>   指定要配置的接口 (默认: lan)
#   -a, --address <IP地址>   设置IP地址 (例如: 192.168.1.1)
#   -m, --mask <子网掩码>    设置子网掩码 (例如: 255.255.255.0 或 24)
#   -g, --gateway <网关>     设置默认网关
#   -d, --dns <DNS服务器>    设置DNS服务器 (用逗号分隔多个服务器)

show_help() {
    echo "网络配置脚本"
    echo "用法: network-config [选项]"
    echo "选项:"
    echo "  -h, --help              显示帮助信息"
    echo "  -i, --interface <接口>   指定要配置的接口 (默认: lan)"
    echo "  -a, --address <IP地址>   设置IP地址 (例如: 192.168.1.1)"
    echo "  -m, --mask <子网掩码>    设置子网掩码 (例如: 255.255.255.0 或 24)"
    echo "  -g, --gateway <网关>     设置默认网关"
    echo "  -d, --dns <DNS服务器>    设置DNS服务器 (用逗号分隔多个服务器)"
    exit 0
}

# 默认值
INTERFACE="lan"
ADDRESS=""
NETMASK=""
GATEWAY=""
DNS=""

# 解析命令行参数
while [ "$1" != "" ]; do
    case $1 in
        -h | --help)
            show_help
            ;;
        -i | --interface)
            shift
            INTERFACE=$1
            ;;
        -a | --address)
            shift
            ADDRESS=$1
            ;;
        -m | --mask)
            shift
            NETMASK=$1
            ;;
        -g | --gateway)
            shift
            GATEWAY=$1
            ;;
        -d | --dns)
            shift
            DNS=$1
            ;;
        *)
            echo "错误: 未知选项 $1"
            show_help
            ;;
    esac
    shift
done

# 检查是否提供了IP地址
if [ -z "$ADDRESS" ]; then
    echo "错误: 必须提供IP地址"
    show_help
fi

# 应用网络配置
echo "正在配置 $INTERFACE 接口..."

# 设置IP地址和子网掩码
uci set network.$INTERFACE.ipaddr="$ADDRESS"
if [ ! -z "$NETMASK" ]; then
    # 检查是否是CIDR格式
    if [[ "$NETMASK" =~ ^[0-9]+$ ]]; then
        # 如果是CIDR格式（如24），设置为前缀长度
        uci set network.$INTERFACE.netmask="$NETMASK"
    else
        # 如果是传统格式（如255.255.255.0），直接设置
        uci set network.$INTERFACE.netmask="$NETMASK"
    fi
fi

# 设置网关
if [ ! -z "$GATEWAY" ]; then
    uci set network.$INTERFACE.gateway="$GATEWAY"
fi

# 设置DNS服务器
if [ ! -z "$DNS" ]; then
    # 删除现有的DNS设置
    uci -q delete network.$INTERFACE.dns
    
    # 添加新的DNS服务器
    IFS=','
    for server in $DNS; do
        uci add_list network.$INTERFACE.dns="$server"
    done
    unset IFS
fi

# 提交更改并重启网络
uci commit network
/etc/init.d/network restart

echo "网络配置已应用到 $INTERFACE 接口"
EOF

    # 设置执行权限
    chmod +x "$script_path"
}

# 添加旁路由设置脚本：提供一键将路由器设置为旁路由模式的功能
add_bypass_router_script() {
    local script_path="$BUILD_DIR/package/base-files/files/usr/bin/set-bypass-mode"
    
    # 确保目录存在
    mkdir -p "$(dirname "$script_path")"
    
    # 创建旁路由设置脚本
    cat <<'EOF' >"$script_path"
#!/bin/sh

# 旁路由设置脚本
# 用法: set-bypass-mode [选项]
# 选项:
#   -h, --help              显示帮助信息
#   -a, --address <IP地址>   设置旁路由IP地址 (例如: 192.168.1.2)
#   -g, --gateway <网关>     设置上级路由器IP地址 (例如: 192.168.1.1)
#   -m, --mask <子网掩码>    设置子网掩码 (例如: 255.255.255.0 或 24)
#   -d, --dns <DNS服务器>    设置DNS服务器 (用逗号分隔多个服务器)
#   -f, --firewall          配置防火墙规则
#   -r, --restore           恢复为正常路由模式

show_help() {
    echo "旁路由设置脚本"
    echo "用法: set-bypass-mode [选项]"
    echo "选项:"
    echo "  -h, --help              显示帮助信息"
    echo "  -a, --address <IP地址>   设置旁路由IP地址 (例如: 192.168.1.2)"
    echo "  -g, --gateway <网关>     设置上级路由器IP地址 (例如: 192.168.1.1)"
    echo "  -m, --mask <子网掩码>    设置子网掩码 (例如: 255.255.255.0 或 24)"
    echo "  -d, --dns <DNS服务器>    设置DNS服务器 (用逗号分隔多个服务器)"
    echo "  -f, --firewall          配置防火墙规则"
    echo "  -r, --restore           恢复为正常路由模式"
    exit 0
}

# 默认值
ADDRESS=""
GATEWAY=""
NETMASK="255.255.255.0"
DNS="223.5.5.5,223.6.6.6"
CONFIGURE_FIREWALL=0
RESTORE_MODE=0

# 解析命令行参数
while [ "$1" != "" ]; do
    case $1 in
        -h | --help)
            show_help
            ;;
        -a | --address)
            shift
            ADDRESS=$1
            ;;
        -g | --gateway)
            shift
            GATEWAY=$1
            ;;
        -m | --mask)
            shift
            NETMASK=$1
            ;;
        -d | --dns)
            shift
            DNS=$1
            ;;
        -f | --firewall)
            CONFIGURE_FIREWALL=1
            ;;
        -r | --restore)
            RESTORE_MODE=1
            ;;
        *)
            echo "错误: 未知选项 $1"
            show_help
            ;;
    esac
    shift
done

# 恢复为正常路由模式
if [ "$RESTORE_MODE" -eq 1 ]; then
    echo "正在恢复为正常路由模式..."
    
    # 恢复LAN接口配置
    uci set network.lan.proto='static'
    uci -q delete network.lan.gateway
    uci -q delete network.lan.dns
    
    # 恢复DHCP服务
    uci set dhcp.lan.ignore='0'
    
    # 恢复防火墙配置
    uci set firewall.@zone[0].masq='1'
    uci set firewall.@zone[0].mtu_fix='1'
    
    # 提交更改并重启服务
    uci commit network
    uci commit dhcp
    uci commit firewall
    
    /etc/init.d/network restart
    /etc/init.d/dnsmasq restart
    /etc/init.d/firewall restart
    
    echo "已恢复为正常路由模式"
    exit 0
fi

# 检查必要参数
if [ -z "$ADDRESS" ]; then
    echo "错误: 必须提供旁路由IP地址"
    show_help
fi

if [ -z "$GATEWAY" ]; then
    echo "错误: 必须提供上级路由器IP地址"
    show_help
fi

echo "正在设置旁路由模式..."

# 配置LAN接口
uci set network.lan.proto='static'
uci set network.lan.ipaddr="$ADDRESS"
uci set network.lan.netmask="$NETMASK"
uci set network.lan.gateway="$GATEWAY"

# 设置DNS服务器
uci -q delete network.lan.dns
IFS=','
for server in $DNS; do
    uci add_list network.lan.dns="$server"
done
unset IFS

# 禁用DHCP服务
uci set dhcp.lan.ignore='1'

# 配置防火墙
if [ "$CONFIGURE_FIREWALL" -eq 1 ]; then
    # 禁用NAT和MTU修复
    uci set firewall.@zone[0].masq='0'
    uci set firewall.@zone[0].mtu_fix='0'
fi

# 提交更改并重启服务
uci commit network
uci commit dhcp
uci commit firewall

/etc/init.d/network restart
/etc/init.d/dnsmasq restart
/etc/init.d/firewall restart

echo "旁路由模式设置完成"
echo "旁路由IP地址: $ADDRESS"
echo "上级路由器IP地址: $GATEWAY"
echo "请将上级路由器的DHCP服务中的网关和DNS设置为 $ADDRESS"
EOF

    # 设置执行权限
    chmod +x "$script_path"
}

# 添加IPv6配置脚本：提供IPv6相关设置功能
add_ipv6_config_script() {
    local script_path="$BUILD_DIR/package/base-files/files/usr/bin/ipv6-config"
    
    # 确保目录存在
    mkdir -p "$(dirname "$script_path")"
    
    # 创建IPv6配置脚本
    cat <<'EOF' >"$script_path"
#!/bin/sh

# IPv6配置脚本
# 用法: ipv6-config [选项]
# 选项:
#   -h, --help              显示帮助信息
#   -e, --enable            启用IPv6
#   -d, --disable           禁用IPv6
#   -m, --mode <模式>        设置IPv6模式 (native, relay, hybrid, passthrough)
#   -r, --router <类型>      设置路由器类型 (main, bypass)
#   -p, --prefix <前缀>      设置IPv6前缀 (用于relay模式)
#   -s, --server <服务器>    设置IPv6中继服务器 (用于relay模式)
#   -u, --upstream <地址>    设置上游路由器IPv6地址 (用于旁路由模式)

show_help() {
    echo "IPv6配置脚本"
    echo "用法: ipv6-config [选项]"
    echo "选项:"
    echo "  -h, --help              显示帮助信息"
    echo "  -e, --enable            启用IPv6"
    echo "  -d, --disable           禁用IPv6"
    echo "  -m, --mode <模式>        设置IPv6模式 (native, relay, hybrid, passthrough)"
    echo "  -r, --router <类型>      设置路由器类型 (main, bypass)"
    echo "  -p, --prefix <前缀>      设置IPv6前缀 (用于relay模式)"
    echo "  -s, --server <服务器>    设置IPv6中继服务器 (用于relay模式)"
    echo "  -u, --upstream <地址>    设置上游路由器IPv6地址 (用于旁路由模式)"
    exit 0
}

# 默认值
ENABLE_IPV6=0
DISABLE_IPV6=0
IPV6_MODE=""
ROUTER_TYPE="main"
IPV6_PREFIX=""
IPV6_SERVER=""
UPSTREAM_IPV6=""

# 解析命令行参数
while [ "$1" != "" ]; do
    case $1 in
        -h | --help)
            show_help
            ;;
        -e | --enable)
            ENABLE_IPV6=1
            ;;
        -d | --disable)
            DISABLE_IPV6=1
            ;;
        -m | --mode)
            shift
            IPV6_MODE=$1
            ;;
        -r | --router)
            shift
            ROUTER_TYPE=$1
            ;;
        -p | --prefix)
            shift
            IPV6_PREFIX=$1
            ;;
        -s | --server)
            shift
            IPV6_SERVER=$1
            ;;
        -u | --upstream)
            shift
            UPSTREAM_IPV6=$1
            ;;
        *)
            echo "错误: 未知选项 $1"
            show_help
            ;;
    esac
    shift
done

# 检查冲突选项
if [ "$ENABLE_IPV6" -eq 1 ] && [ "$DISABLE_IPV6" -eq 1 ]; then
    echo "错误: 不能同时启用和禁用IPv6"
    show_help
fi

# 检查路由器类型
if [ "$ROUTER_TYPE" != "main" ] && [ "$ROUTER_TYPE" != "bypass" ]; then
    echo "错误: 路由器类型必须是 main 或 bypass"
    show_help
fi

# 如果是旁路由模式，检查上游IPv6地址
if [ "$ROUTER_TYPE" = "bypass" ] && [ "$ENABLE_IPV6" -eq 1 ] && [ -z "$UPSTREAM_IPV6" ]; then
    echo "错误: 旁路由模式需要指定上游路由器IPv6地址"
    show_help
fi

# 禁用IPv6
if [ "$DISABLE_IPV6" -eq 1 ]; then
    echo "正在禁用IPv6..."
    
    # 禁用内核IPv6
    uci set 'network.globals=globals'
    uci set network.globals.ula_prefix=''
    uci set network.globals.packet_steering='1'
    
    # 禁用所有接口的IPv6
    for iface in $(uci show network | grep "\.proto=" | cut -d. -f2); do
        uci -q delete network.$iface.ip6assign
        uci -q delete network.$iface.ip6hint
        uci -q delete network.$iface.ip6class
        uci -q delete network.$iface.ip6prefix
        uci -q delete network.$iface.ip6ifaceid
    done
    
    # 禁用DHCPv6服务
    for iface in $(uci show dhcp | grep "\.dhcpv6=" | cut -d. -f2); do
        uci set dhcp.$iface.dhcpv6='disabled'
        uci set dhcp.$iface.ra='disabled'
        uci set dhcp.$iface.ndp='disabled'
    done
    
    # 提交更改并重启服务
    uci commit network
    uci commit dhcp
    /etc/init.d/network restart
    /etc/init.d/dnsmasq restart
    
    echo "IPv6已禁用"
    exit 0
fi

# 启用IPv6
if [ "$ENABLE_IPV6" -eq 1 ]; then
    echo "正在启用IPv6..."
    
    # 启用内核IPv6
    uci set 'network.globals=globals'
    uci set network.globals.ula_prefix='fd00::/48'
    
    # 主路由模式配置
    if [ "$ROUTER_TYPE" = "main" ]; then
        # 根据指定的模式配置IPv6
        case "$IPV6_MODE" in
            native)
                echo "配置主路由本地IPv6模式..."
                
                # 配置LAN接口
                uci set network.lan.ip6assign='60'
                
                # 配置WAN接口
                uci set network.wan.ipv6='1'
                uci set network.wan.delegate='0'
                
                # 确保wan6接口存在
                uci -q delete network.wan6
                uci set network.wan6=interface
                uci set network.wan6.proto='dhcpv6'
                
                # 检查设备是否支持@wan格式，如果不支持则使用实际接口名
                local wan_device=$(uci -q get network.wan.device)
                if [ -n "$wan_device" ]; then
                    uci set network.wan6.device="$wan_device"
                else
                    # 尝试使用@wan格式
                    uci set network.wan6.device='@wan'
                fi
                
                uci set network.wan6.reqaddress='try'
                uci set network.wan6.reqprefix='auto'
                
                # 配置DHCPv6服务
                uci set dhcp.lan.dhcpv6='server'
                uci set dhcp.lan.ra='server'
                uci set dhcp.lan.ra_management='1'
                uci set dhcp.lan.ra_default='1'
                ;;
                
            relay)
                echo "配置主路由IPv6中继模式..."
                
                if [ -z "$IPV6_PREFIX" ]; then
                    echo "错误: 中继模式需要指定IPv6前缀"
                    exit 1
                fi
                
                if [ -z "$IPV6_SERVER" ]; then
                    echo "错误: 中继模式需要指定IPv6中继服务器"
                    exit 1
                fi
                
                # 配置LAN接口
                uci set network.lan.ip6assign='60'
                
                # 配置WAN接口
                uci set network.wan.ipv6='1'
                
                # 配置6in4接口
                uci -q delete network.wan6
                uci set network.wan6=interface
                uci set network.wan6.proto='6in4'
                uci set network.wan6.peeraddr="$IPV6_SERVER"
                uci set network.wan6.ip6prefix="$IPV6_PREFIX"
                uci set network.wan6.tunnelid='1'
                
                # 配置DHCPv6服务
                uci set dhcp.lan.dhcpv6='server'
                uci set dhcp.lan.ra='server'
                uci set dhcp.lan.ra_management='1'
                ;;
                
            hybrid)
                echo "配置主路由混合IPv6模式..."
                
                # 配置LAN接口
                uci set network.lan.ip6assign='60'
                
                # 配置WAN接口
                uci set network.wan.ipv6='1'
                uci set network.wan.delegate='0'
                
                # 配置DHCPv6客户端
                uci -q delete network.wan6
                uci set network.wan6=interface
                uci set network.wan6.proto='dhcpv6'
                
                # 检查设备是否支持@wan格式，如果不支持则使用实际接口名
                local wan_device=$(uci -q get network.wan.device)
                if [ -n "$wan_device" ]; then
                    uci set network.wan6.device="$wan_device"
                else
                    # 尝试使用@wan格式
                    uci set network.wan6.device='@wan'
                fi
                
                uci set network.wan6.reqaddress='try'
                uci set network.wan6.reqprefix='auto'
                
                # 配置DHCPv6服务
                uci set dhcp.lan.dhcpv6='hybrid'
                uci set dhcp.lan.ra='hybrid'
                uci set dhcp.lan.ndp='hybrid'
                ;;
                
            passthrough)
                echo "配置主路由IPv6透传模式..."
                
                # 配置LAN接口
                uci -q delete network.lan.ip6assign
                
                # 配置WAN接口
                uci set network.wan.ipv6='1'
                uci set network.wan.delegate='1'
                
                # 配置DHCPv6服务
                uci set dhcp.lan.dhcpv6='relay'
                uci set dhcp.lan.ra='relay'
                uci set dhcp.lan.ndp='relay'
                uci set dhcp.lan.master='1'
                ;;
                
            *)
                echo "错误: 未知的IPv6模式 '$IPV6_MODE'"
                echo "支持的模式: native, relay, hybrid, passthrough"
                exit 1
                ;;
        esac
    
    # 旁路由模式配置
    elif [ "$ROUTER_TYPE" = "bypass" ]; then
        echo "配置旁路由IPv6模式..."
        
        if [ -z "$UPSTREAM_IPV6" ]; then
            echo "错误: 旁路由模式需要指定上游路由器IPv6地址"
            exit 1
        fi
        
        # 配置LAN接口
        uci -q delete network.lan.ip6assign
        
        # 配置静态IPv6地址
        uci set network.lan.ip6addr="$UPSTREAM_IPV6"
        
        # 禁用DHCPv6服务
        uci set dhcp.lan.dhcpv6='disabled'
        uci set dhcp.lan.ra='disabled'
        uci set dhcp.lan.ndp='disabled'
        
        # 启用IPv6转发
        uci set network.@globals[0].packet_steering='1'
        
        echo "旁路由IPv6已配置，使用上游地址: $UPSTREAM_IPV6"
    fi
    
    # 提交更改并重启服务
    uci commit network
    uci commit dhcp
    /etc/init.d/network restart
    /etc/init.d/dnsmasq restart
    
    echo "IPv6已启用，路由器类型: $ROUTER_TYPE"
    exit 0
fi

# 如果没有指定操作，显示帮助信息
show_help
EOF

    # 设置执行权限
    chmod +x "$script_path"
}


# 更新golang：使用指定的golang仓库替换原有的golang包
update_golang() {
    if [[ -d ./feeds/packages/lang/golang ]]; then
        \rm -rf ./feeds/packages/lang/golang
        git clone $GOLANG_REPO -b $GOLANG_BRANCH ./feeds/packages/lang/golang
    fi
}

# 安装small8源中的包：安装指定的网络工具和LuCI应用
install_small8() {
    ./scripts/feeds install -p small8 -f xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy shadowsocks-rust sing-box v2ray-core v2ray-geodata v2ray-geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        luci-app-passwall alist luci-app-alist smartdns luci-app-smartdns v2dat mosdns luci-app-mosdns \
        adguardhome luci-app-adguardhome ddns-go luci-app-ddns-go taskd luci-lib-xterm luci-lib-taskd \
        luci-app-store quickstart luci-app-quickstart luci-app-istorex luci-app-cloudflarespeedtest \
        luci-theme-argon netdata luci-app-netdata lucky luci-app-lucky luci-app-openclash luci-app-homeproxy \
        luci-app-amlogic nikki luci-app-nikki tailscale luci-app-tailscale oaf open-app-filter luci-app-oaf \
        easytier luci-app-easytier
}

# 安装feeds：更新并安装所有feeds源中的包
install_feeds() {
    ./scripts/feeds update -i
    for dir in $BUILD_DIR/feeds/*; do
        # 检查是否为目录并且不以 .tmp 结尾，并且不是软链接
        if [ -d "$dir" ] && [[ ! "$dir" == *.tmp ]] && [ ! -L "$dir" ]; then
            if [[ $(basename "$dir") == "small8" ]]; then
                install_small8
            else
                ./scripts/feeds install -f -ap $(basename "$dir")
            fi
        fi
    done
}

# 修复默认设置：设置默认主题和其他UI相关配置
fix_default_set() {
    # 修改默认主题
    if [ -d "$BUILD_DIR/feeds/luci/collections/" ]; then
        find "$BUILD_DIR/feeds/luci/collections/" -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$THEME_SET/g" {} \;
    fi

    # 修改argon主题的CSS变量
    if [ -d "$BUILD_DIR/feeds/small8/luci-theme-argon" ]; then
        find "$BUILD_DIR/feeds/small8/luci-theme-argon" -type f -name "cascade*" -exec sed -i 's/--bar-bg/--primary/g' {} \;
    fi

    # 安装argon主题的主色调设置脚本
    install -Dm755 "$BASE_PATH/patches/99_set_argon_primary" "$BUILD_DIR/package/base-files/files/etc/uci-defaults/99_set_argon_primary"

    # 复制温度信息脚本（如果存在）
    if [ -f "$BUILD_DIR/package/emortal/autocore/files/tempinfo" ]; then
        if [ -f "$BASE_PATH/patches/tempinfo" ]; then
            \cp -f "$BASE_PATH/patches/tempinfo" "$BUILD_DIR/package/emortal/autocore/files/tempinfo"
        fi
    fi
}

# 修复miniupnpd：为特定版本的miniupnpd应用补丁
fix_miniupmpd() {
    # 从 miniupnpd 的 Makefile 中提取 PKG_HASH 的值
    local PKG_HASH=$(grep '^PKG_HASH:=' "$BUILD_DIR/feeds/packages/net/miniupnpd/Makefile" 2>/dev/null | cut -d '=' -f 2)

    # 检查 miniupnp 版本，并且补丁文件是否存在
    if [[ $PKG_HASH == "fbdd5501039730f04a8420ea2f8f54b7df63f9f04cde2dc67fa7371e80477bbe" && -f "$BASE_PATH/patches/400-fix_nft_miniupnp.patch" ]]; then
        # 使用 install 命令创建目录并复制补丁文件
        install -Dm644 "$BASE_PATH/patches/400-fix_nft_miniupnp.patch" "$BUILD_DIR/feeds/packages/net/miniupnpd/patches/400-fix_nft_miniupnp.patch"
    fi
}

# 将dnsmasq替换为dnsmasq-full：提供更多功能的DNS服务
change_dnsmasq2full() {
    if ! grep -q "dnsmasq-full" $BUILD_DIR/include/target.mk; then
        sed -i 's/dnsmasq/dnsmasq-full/g' ./include/target.mk
    fi
}

# 检查并添加fullconenat支持：用于改善NAT穿透性能
chk_fullconenat() {
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat-nft ]; then
        \cp -rf $BASE_PATH/fullconenat/fullconenat-nft $BUILD_DIR/package/network/utils
    fi
    if [ ! -d $BUILD_DIR/package/network/utils/fullconenat ]; then
        \cp -rf $BASE_PATH/fullconenat/fullconenat $BUILD_DIR/package/network/utils
    fi
}

# 修复默认依赖：将mbedtls替换为openssl以提供更好的兼容性
fix_mk_def_depends() {
    sed -i 's/libustream-mbedtls/libustream-openssl/g' $BUILD_DIR/include/target.mk 2>/dev/null
    if [ -f $BUILD_DIR/target/linux/qualcommax/Makefile ]; then
        sed -i 's/wpad-basic-mbedtls/wpad-openssl/g' $BUILD_DIR/target/linux/qualcommax/Makefile
    fi
}

# 添加WiFi默认设置：为不同平台添加WiFi配置脚本
add_wifi_default_set() {
    local qualcommax_uci_dir="$BUILD_DIR/target/linux/qualcommax/base-files/etc/uci-defaults"
    local filogic_uci_dir="$BUILD_DIR/target/linux/mediatek/filogic/base-files/etc/uci-defaults"
    if [ -d "$qualcommax_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$qualcommax_uci_dir/992_set-wifi-uci.sh"
    fi
    if [ -d "$filogic_uci_dir" ]; then
        install -Dm755 "$BASE_PATH/patches/992_set-wifi-uci.sh" "$filogic_uci_dir/992_set-wifi-uci.sh"
    fi
}

# 更新默认LAN地址：修改默认的LAN IP地址
update_default_lan_addr() {
    local CFG_PATH="$BUILD_DIR/package/base-files/files/bin/config_generate"
    if [ -f $CFG_PATH ]; then
        sed -i 's/192\.168\.[0-9]*\.[0-9]*/'$LAN_ADDR'/g' $CFG_PATH
    fi
}

# 移除不需要的NSS内核模块：删除不必要的网络子系统模块以减少固件大小
remove_something_nss_kmod() {
    local ipq_target_path="$BUILD_DIR/target/linux/qualcommax/ipq60xx/target.mk"
    local ipq_mk_path="$BUILD_DIR/target/linux/qualcommax/Makefile"
    if [ -f $ipq_target_path ]; then
        # 从ipq60xx目标配置中移除不需要的NSS驱动模块
        sed -i 's/kmod-qca-nss-drv-eogremgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-gre//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-map-t//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-match//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-mirror//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-pvxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tun6rd//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-tunipip6//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-drv-vxlanmgr//g' $ipq_target_path
        sed -i 's/kmod-qca-nss-macsec//g' $ipq_target_path
    fi

    if [ -f $ipq_mk_path ]; then
        # 从qualcommax平台Makefile中完全删除NSS相关行
        sed -i '/kmod-qca-nss-crypto/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-eogremgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-gre/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-map-t/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-match/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-mirror/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-tun6rd/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-tunipip6/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-vxlanmgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-drv-wifi-meshmgr/d' $ipq_mk_path
        sed -i '/kmod-qca-nss-macsec/d' $ipq_mk_path

        # 移除CPU频率调节模块
        sed -i 's/cpufreq //g' $ipq_mk_path
    fi
}

# 更新中断亲和性脚本：替换默认的中断亲和性配置脚本
update_affinity_script() {
    local affinity_script_dir="$BUILD_DIR/target/linux/qualcommax"

    if [ -d "$affinity_script_dir" ]; then
        # 删除旧的中断亲和性脚本
        find "$affinity_script_dir" -name "set-irq-affinity" -exec rm -f {} \;
        find "$affinity_script_dir" -name "smp_affinity" -exec rm -f {} \;
        # 安装新的中断亲和性脚本
        install -Dm755 "$BASE_PATH/patches/smp_affinity" "$affinity_script_dir/base-files/etc/init.d/smp_affinity"
    fi
}

# 修复OpenSSL构建：启用SSL3支持
fix_build_for_openssl() {
    local makefile="$BUILD_DIR/package/libs/openssl/Makefile"

    if [[ -f "$makefile" ]]; then
        if ! grep -qP "^CONFIG_OPENSSL_SSL3" "$makefile"; then
            # 添加SSL3支持配置
            sed -i '/^ifndef CONFIG_OPENSSL_SSL3/i CONFIG_OPENSSL_SSL3 := y' "$makefile"
        fi
    fi
}

# 更新ath11k固件：从指定仓库获取最新的ath11k固件Makefile
update_ath11k_fw() {
    local makefile="$BUILD_DIR/package/firmware/ath11k-firmware/Makefile"
    local new_mk="$BASE_PATH/patches/ath11k_fw.mk"

    if [ -d "$(dirname "$makefile")" ] && [ -f "$makefile" ]; then
        # 删除旧的临时文件（如果存在）
        [ -f "$new_mk" ] && \rm -f "$new_mk"
        # 下载最新的Makefile
        curl -L -o "$new_mk" https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/refs/heads/main/package/firmware/ath11k-firmware/Makefile
        # 替换原有的Makefile
        \mv -f "$new_mk" "$makefile"
    fi
}

# 修复软件包格式无效问题：修正特定软件包的版本格式
fix_mkpkg_format_invalid() {
    if [[ $BUILD_DIR =~ "imm-nss" ]]; then
        # 修复v2ray-geodata包的版本格式
        if [ -f $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile ]; then
            sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' $BUILD_DIR/feeds/small8/v2ray-geodata/Makefile
        fi
        # 修复luci-lib-taskd包的依赖版本格式
        if [ -f $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile ]; then
            sed -i 's/>=1\.0\.3-1/>=1\.0\.3-r1/g' $BUILD_DIR/feeds/small8/luci-lib-taskd/Makefile
        fi
        # 修复luci-app-openclash包的发布版本格式
        if [ -f $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile ]; then
            sed -i 's/PKG_RELEASE:=beta/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-openclash/Makefile
        fi
        # 修复luci-app-quickstart包的版本格式
        if [ -f $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.8\.16-1/PKG_VERSION:=0\.8\.16/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-quickstart/Makefile
        fi
        # 修复luci-app-store包的版本格式
        if [ -f $BUILD_DIR/feeds/small8/luci-app-store/Makefile ]; then
            sed -i 's/PKG_VERSION:=0\.1\.27-1/PKG_VERSION:=0\.1\.27/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
            sed -i 's/PKG_RELEASE:=$/PKG_RELEASE:=1/g' $BUILD_DIR/feeds/small8/luci-app-store/Makefile
        fi
    fi
}

# 添加AX6600 LED控制应用：用于控制Redmi AX6600路由器的LED灯
add_ax6600_led() {
    local athena_led_dir="$BUILD_DIR/package/emortal/luci-app-athena-led"

    # 删除旧的目录（如果存在）
    rm -rf "$athena_led_dir" 2>/dev/null

    # 克隆最新的仓库
    git clone --depth=1 https://github.com/NONGFAH/luci-app-athena-led.git "$athena_led_dir"
    # 设置执行权限
    chmod +x "$athena_led_dir/root/usr/sbin/athena-led"
    chmod +x "$athena_led_dir/root/etc/init.d/athena_led"
}

# 修改CPU使用率获取方式：优化CPU使用率显示
chanage_cpuusage() {
    local luci_dir="$BUILD_DIR/feeds/luci/modules/luci-base/root/usr/share/rpcd/ucode/luci"
    local imm_script1="$BUILD_DIR/package/base-files/files/sbin/cpuusage"

    # 修改LuCI基础模块中获取CPU使用率的方法
    if [ -f $luci_dir ]; then
        # 替换原有的CPU使用率获取命令，优先使用/sbin/cpuusage脚本
        sed -i "s#const fd = popen('top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\'')#const cpuUsageCommand = access('/sbin/cpuusage') ? '/sbin/cpuusage' : 'top -n1 | awk \\\'/^CPU/ {printf(\"%d%\", 100 - \$8)}\\\''#g" $luci_dir
        # 添加使用新命令的代码
        sed -i '/cpuUsageCommand/a \\t\t\tconst fd = popen(cpuUsageCommand);' $luci_dir
    fi

    # 删除旧的cpuusage脚本（如果存在）
    if [ -f "$imm_script1" ]; then
        rm -f "$imm_script1"
    fi

    # 为不同平台安装定制的CPU使用率脚本
    install -Dm755 "$BASE_PATH/patches/cpuusage" "$BUILD_DIR/target/linux/qualcommax/base-files/sbin/cpuusage"
    install -Dm755 "$BASE_PATH/patches/hnatusage" "$BUILD_DIR/target/linux/mediatek/filogic/base-files/sbin/cpuusage"
}

# 更新tcping工具：使用最新版本的tcping
update_tcping() {
    local tcping_path="$BUILD_DIR/feeds/small8/tcping/Makefile"

    if [ -d "$(dirname "$tcping_path")" ] && [ -f "$tcping_path" ]; then
        # 删除旧的Makefile
        \rm -f "$tcping_path"
        # 下载最新的Makefile
        curl -L -o "$tcping_path" https://raw.githubusercontent.com/xiaorouji/openwrt-passwall-packages/refs/heads/main/tcping/Makefile
    fi
}

# 设置自定义任务：添加系统启动时执行的定时任务
set_custom_task() {
    local sh_dir="$BUILD_DIR/package/base-files/files/etc/init.d"
    # 创建自定义任务启动脚本
    cat <<'EOF' >"$sh_dir/custom_task"
#!/bin/sh /etc/rc.common
# 设置启动优先级
START=99

boot() {
    # 重新添加缓存请求定时任务
    sed -i '/drop_caches/d' /etc/crontabs/root
    echo "15 3 * * * sync && echo 3 > /proc/sys/vm/drop_caches" >>/etc/crontabs/root

    # 删除现有的 wireguard_check 任务
    sed -i '/wireguard_check/d' /etc/crontabs/root

    # 获取 WireGuard 接口名称
    local wg_ifname=$(wg show | awk '/interface/ {print $2}')

    if [ -n "$wg_ifname" ]; then
        # 添加新的 wireguard_check 任务，每10分钟执行一次
        echo "*/10 * * * * /sbin/wireguard_check.sh" >>/etc/crontabs/root
        uci set system.@system[0].cronloglevel='9'
        uci commit system
        /etc/init.d/cron restart
    fi

    # 应用新的 crontab 配置
    crontab /etc/crontabs/root
}
EOF
    # 设置脚本执行权限
    chmod +x "$sh_dir/custom_task"
}

# 添加WireGuard检查脚本：用于监控WireGuard连接状态
add_wg_chk() {
    local sbin_path="$BUILD_DIR/package/base-files/files/sbin"
    if [[ -d "$sbin_path" ]]; then
        # 安装WireGuard检查脚本
        install -Dm755 "$BASE_PATH/patches/wireguard_check.sh" "$sbin_path/wireguard_check.sh"
    fi
}

# 更新PassWall的HAProxy检查：优化PassWall的HAProxy配置
update_pw_ha_chk() {
    local new_path="$BASE_PATH/patches/haproxy_check.sh"
    local pw_share_dir="$BUILD_DIR/feeds/small8/luci-app-passwall/root/usr/share/passwall"
    local pw_ha_path="$pw_share_dir/haproxy_check.sh"
    local ha_lua_path="$pw_share_dir/haproxy.lua"
    local smartdns_lua_path="$pw_share_dir/helper_smartdns_add.lua"
    local rules_dir="$pw_share_dir/rules"

    # 修改 haproxy.lua 文件中的 rise 和 fall 参数，提高连接稳定性
    [ -f "$ha_lua_path" ] && sed -i 's/rise 1 fall 3/rise 3 fall 2/g' "$ha_lua_path"

    # 删除 helper_smartdns_add.lua 文件中的特定行，优化DNS解析
    [ -f "$smartdns_lua_path" ] && sed -i '/force-qtype-SOA 65/d' "$smartdns_lua_path"

    # 从 chnlist 文件中删除特定的域名
    if [ -f "$rules_dir/chnlist" ]; then
        sed -i '/\.bing\./d' "$rules_dir/chnlist"
        sed -i '/microsoft/d' "$rules_dir/chnlist"
        sed -i '/msedge/d' "$rules_dir/chnlist"
        sed -i '/github/d' "$rules_dir/chnlist"
    fi
}

# 安装OPKG源配置：添加ImmortalWrt官方软件源
install_opkg_distfeeds() {
    local emortal_def_dir="$BUILD_DIR/package/emortal/default-settings"
    local distfeeds_conf="$emortal_def_dir/files/99-distfeeds.conf"

    if [ -d "$emortal_def_dir" ] && [ ! -f "$distfeeds_conf" ]; then
        # 创建软件源配置文件
        cat <<'EOF' >"$distfeeds_conf"
src/gz openwrt_base https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base/
src/gz openwrt_luci https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci/
src/gz openwrt_packages https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages/
src/gz openwrt_routing https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing/
src/gz openwrt_telephony https://downloads.immortalwrt.org/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony/
EOF

        # 修改Makefile，添加安装配置文件的命令
        sed -i "/define Package\/default-settings\/install/a\\
\\t\$(INSTALL_DIR) \$(1)/etc\\n\
\t\$(INSTALL_DATA) ./files/99-distfeeds.conf \$(1)/etc/99-distfeeds.conf\n" $emortal_def_dir/Makefile

        # 修改默认设置脚本，添加移动配置文件和禁用签名检查的命令
        sed -i "/exit 0/i\\
[ -f \'/etc/99-distfeeds.conf\' ] && mv \'/etc/99-distfeeds.conf\' \'/etc/opkg/distfeeds.conf\'\n\
sed -ri \'/check_signature/s@^[^#]@#&@\' /etc/opkg.conf\n" $emortal_def_dir/files/99-default-settings
    fi
}

# 更新NSS PBUF性能设置：优化网络性能
update_nss_pbuf_performance() {
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/pbuf.uci"
    if [ -d "$(dirname "$pbuf_path")" ] && [ -f $pbuf_path ]; then
        # 禁用自动缩放
        sed -i "s/auto_scale '1'/auto_scale 'off'/g" $pbuf_path
        # 将CPU调度器从performance改为schedutil以平衡性能和功耗
        sed -i "s/scaling_governor 'performance'/scaling_governor 'schedutil'/g" $pbuf_path
    fi
}

# 设置构建签名：在LuCI状态页面添加构建者信息
set_build_signature() {
    local file="$BUILD_DIR/feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js"
    if [ -d "$(dirname "$file")" ] && [ -f $file ]; then
        # 在LuCI版本信息后添加构建者标识
        sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ build by ZqinKing')/g" "$file"
    fi
}

# 修复vlmcsd编译问题：添加补丁以解决与ccache的兼容性问题
fix_compile_vlmcsd() {
    local dir="$BUILD_DIR/feeds/packages/net/vlmcsd"
    local patch_src="$BASE_PATH/patches/001-fix_compile_with_ccache.patch"
    local patch_dest="$dir/patches"

    if [ -d "$dir" ]; then
        # 创建补丁目录并复制补丁文件
        mkdir -p "$patch_dest"
        cp -f "$patch_src" "$patch_dest"
    fi
}

# 更新NSS诊断脚本：替换为优化版本的诊断工具
update_nss_diag() {
    local file="$BUILD_DIR/package/kernel/mac80211/files/nss_diag.sh"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        # 删除旧的诊断脚本
        \rm -f "$file"
        # 安装新的诊断脚本
        install -Dm755 "$BASE_PATH/patches/nss_diag.sh" "$file"
    fi
}

# 更新菜单位置：调整LuCI界面中应用的分类
update_menu_location() {
    # 将Samba4从NAS分类移动到服务分类
    local samba4_path="$BUILD_DIR/feeds/luci/applications/luci-app-samba4/root/usr/share/luci/menu.d/luci-app-samba4.json"
    if [ -d "$(dirname "$samba4_path")" ] && [ -f "$samba4_path" ]; then
        sed -i 's/nas/services/g' "$samba4_path"
    fi

    # 将Tailscale从服务分类移动到VPN分类
    local tailscale_path="$BUILD_DIR/feeds/small8/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    if [ -d "$(dirname "$tailscale_path")" ] && [ -f "$tailscale_path" ]; then
        sed -i 's/services/vpn/g' "$tailscale_path"
    fi
}

# 修复CoreMark编译问题：修正Makefile中的mkdir命令
fix_compile_coremark() {
    local file="$BUILD_DIR/feeds/packages/utils/coremark/Makefile"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        # 添加-p参数以确保目录创建成功
        sed -i 's/mkdir \$/mkdir -p \$/g' "$file"
    fi
}

# 更新HomeProxy：使用ImmortalWrt官方仓库的最新版本
update_homeproxy() {
    local repo_url="https://github.com/immortalwrt/homeproxy.git"
    local target_dir="$BUILD_DIR/feeds/small8/luci-app-homeproxy"

    if [ -d "$target_dir" ]; then
        # 删除旧版本
        rm -rf "$target_dir"
        # 克隆最新版本
        git clone "$repo_url" "$target_dir"
    fi
}

# 更新Dnsmasq配置：移除DNS重定向选项
update_dnsmasq_conf() {
    local file="$BUILD_DIR/package/network/services/dnsmasq/files/dhcp.conf"
    if [ -d "$(dirname "$file")" ] && [ -f "$file" ]; then
        # 删除DNS重定向相关配置
        sed -i '/dns_redirect/d' "$file"
    fi
}

# 更新软件包版本：从GitHub获取最新版本并更新Makefile
update_package() {
    local dir=$(find "$BUILD_DIR/package" \( -type d -o -type l \) -name $1)
    if [ -z $dir ]; then
        return 0
    fi
    local mk_path="$dir/Makefile"
    if [ -f "$mk_path" ]; then
        # 提取GitHub仓库信息
        local PKG_REPO=$(grep -oE "^PKG_SOURCE_URL.*github.com(/[-_a-zA-Z0-9]{1,}){2}" $mk_path | awk -F"/" '{print $(NF - 1) "/" $NF}')
        if [ -z $PKG_REPO ]; then
            return 0
        fi
        # 获取最新的非预发布版本
        local PKG_VER=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease|not)) | first | .tag_name")
        PKG_VER=$(echo $PKG_VER | grep -oE "[\.0-9]{1,}")

        # 提取包名和源文件信息
        local PKG_NAME=$(awk -F"=" '/PKG_NAME:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE=$(awk -F"=" '/PKG_SOURCE:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")
        local PKG_SOURCE_URL=$(awk -F"=" '/PKG_SOURCE_URL:=/ {print $NF}' $mk_path | grep -oE "[-_:/\$\(\)\?\.a-zA-Z0-9]{1,}")

        # 替换变量
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE_URL=${PKG_SOURCE_URL//\$\(PKG_VERSION\)/$PKG_VER}
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_NAME\)/$PKG_NAME}
        PKG_SOURCE=${PKG_SOURCE//\$\(PKG_VERSION\)/$PKG_VER}

        # 计算新源文件的哈希值
        local PKG_HASH=$(curl -sL "$PKG_SOURCE_URL""$PKG_SOURCE" | sha256sum | cut -b -64)

        # 更新Makefile中的版本和哈希值
        sed -i 's/^PKG_VERSION:=.*/PKG_VERSION:='$PKG_VER'/g' $mk_path
        sed -i 's/^PKG_HASH:=.*/PKG_HASH:='$PKG_HASH'/g' $mk_path

        echo "Update Package $1 to $PKG_VER $PKG_HASH"
    fi
}

# 更新Lucky应用：使用本地预编译的二进制文件
update_lucky() {
    local mk_dir="$BUILD_DIR/feeds/small8/lucky/Makefile"
    if [ -d "${mk_dir%/*}" ] && [ -f "$mk_dir" ]; then
        # 添加使用本地预编译二进制文件的支持
        sed -i '/Build\/Prepare/ a\	[ -f $(TOPDIR)/../patches/lucky_Linux_$(LUCKY_ARCH).tar.gz ] && install -Dm644 $(TOPDIR)/../patches/lucky_Linux_$(LUCKY_ARCH).tar.gz $(PKG_BUILD_DIR)/$(PKG_NAME)_$(PKG_VERSION)_Linux_$(LUCKY_ARCH).tar.gz' "$mk_dir"
        # 删除wget下载命令
        sed -i '/wget/d' "$mk_dir"
    fi
}

# 添加系统升级时的备份信息：确保重要配置在升级后保留
function add_backup_info_to_sysupgrade() {
    local conf_path="$BUILD_DIR/package/base-files/files/etc/sysupgrade.conf"

    if [ -f "$conf_path" ]; then
        # 添加需要在系统升级时保留的文件和目录
        cat >"$conf_path" <<'EOF'
/etc/AdGuardHome.yaml
/etc/easytier
/etc/lucky/
EOF
    fi
}

# 更新启动顺序：调整服务启动优先级以确保正确的依赖关系
function update_script_priority() {
    # 更新qca-nss驱动的启动顺序
    local qca_drv_path="$BUILD_DIR/package/feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
    if [ -d "${qca_drv_path%/*}" ] && [ -f "$qca_drv_path" ]; then
        sed -i 's/START=.*/START=88/g' "$qca_drv_path"
    fi

    # 更新pbuf服务的启动顺序
    local pbuf_path="$BUILD_DIR/package/kernel/mac80211/files/qca-nss-pbuf.init"
    if [ -d "${pbuf_path%/*}" ] && [ -f "$pbuf_path" ]; then
        sed -i 's/START=.*/START=89/g' "$pbuf_path"
    fi

    # 更新mosdns服务的启动顺序
    local mosdns_path="$BUILD_DIR/package/feeds/small8/luci-app-mosdns/root/etc/init.d/mosdns"
    if [ -d "${mosdns_path%/*}" ] && [ -f "$mosdns_path" ]; then
        sed -i 's/START=.*/START=94/g' "$mosdns_path"
    fi
}

# 优化SmartDNS配置：提高DNS解析性能
function optimize_smartDNS() {
    local smartdns_custom="$BUILD_DIR/feeds/small8/smartdns/conf/custom.conf"
    local smartdns_patch="$BUILD_DIR/feeds/small8/smartdns/patches/010_change_start_order.patch"
    # 安装启动顺序修改补丁
    install -Dm644 "$BASE_PATH/patches/010_change_start_order.patch" "$smartdns_patch"

    # 检查配置文件所在的目录和文件是否存在
    if [ -d "${smartdns_custom%/*}" ] && [ -f "$smartdns_custom" ]; then
        # 优化配置选项：
        # serve-expired-ttl: 缓存有效期(单位：小时)，默认值影响DNS解析速度
        # serve-expired-reply-ttl: 过期回复TTL
        # max-reply-ip-num: 最大IP数
        # dualstack-ip-selection-threshold: IPv6优先的阈值
        # server: 配置上游DNS
        echo "优化SmartDNS配置"
        cat >"$smartdns_custom" <<'EOF'
serve-expired-ttl 7200
serve-expired-reply-ttl 5
max-reply-ip-num 3
dualstack-ip-selection-threshold 15
server 223.5.5.5 -bootstrap-dns
EOF
    fi
}

# 更新MosDNS默认配置：调整缓存和端口设置
update_mosdns_deconfig() {
    local mosdns_conf="$BUILD_DIR/feeds/small8/luci-app-mosdns/root/etc/config/mosdns"
    if [ -d "${mosdns_conf%/*}" ] && [ -f "$mosdns_conf" ]; then
        # 将缓存大小从8000减少到300，减少内存占用
        sed -i 's/8000/300/g' "$mosdns_conf"
        # 将监听端口从5335改为5336，避免与其他DNS服务冲突
        sed -i 's/5335/5336/g' "$mosdns_conf"
    fi
}

# 修复QuickStart应用：替换索引文件以解决兼容性问题
fix_quickstart() {
    local qs_index_path="$BUILD_DIR/feeds/small8/luci-app-quickstart/htdocs/luci-static/quickstart/index.js"
    local fix_path="$BASE_PATH/patches/quickstart_index.js"
    if [ -f "$qs_index_path" ] && [ -f "$fix_path" ]; then
        # 用修复版本替换原始索引文件
        cat "$fix_path" >"$qs_index_path"
    else
        echo "Quickstart index.js 或补丁文件不存在，请检查路径是否正确。"
    fi
}

# 更新应用过滤器默认配置：优化性能和用户体验
update_oaf_deconfig() {
    local conf_path="$BUILD_DIR/feeds/small8/open-app-filter/files/appfilter.config"
    local uci_def="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/94_feature_3.0"
    local disable_path="$BUILD_DIR/feeds/small8/luci-app-oaf/root/etc/uci-defaults/99_disable_oaf"

    if [ -d "${conf_path%/*}" ] && [ -f "$conf_path" ]; then
        # 修改默认配置：
        # - 禁用记录功能以减少资源占用
        # - 启用硬件NAT加速以提高性能
        # - 禁用自动加载引擎以允许用户手动控制
        sed -i \
            -e "s/record_enable '1'/record_enable '0'/g" \
            -e "s/disable_hnat '1'/disable_hnat '0'/g" \
            -e "s/auto_load_engine '1'/auto_load_engine '0'/g" \
            "$conf_path"
    fi

    if [ -d "${uci_def%/*}" ] && [ -f "$uci_def" ]; then
        # 从UCI默认设置中删除冲突的配置行
        sed -i '/\(disable_hnat\|auto_load_engine\)/d' "$uci_def"

        # 创建禁用脚本：如果应用过滤器被设置为禁用，则停止服务
        cat >"$disable_path" <<-EOF
#!/bin/sh
[ "\$(uci get appfilter.global.enable 2>/dev/null)" = "0" ] && {
    /etc/init.d/appfilter disable
    /etc/init.d/appfilter stop
}
EOF
        chmod +x "$disable_path"
    fi
}

# 添加网络设置功能到主函数
main() {
    # 基础设置
    clone_repo                # 克隆仓库
    clean_up                  # 清理构建环境
    reset_feeds_conf          # 重置feeds配置
    update_feeds              # 更新feeds配置
    remove_unwanted_packages  # 移除不需要的包
    update_homeproxy          # 更新HomeProxy
    fix_default_set           # 修复默认设置
    fix_miniupmpd             # 修复miniupnpd
    update_golang             # 更新golang
    
    # 网络配置优化
    change_dnsmasq2full       # 将dnsmasq替换为dnsmasq-full
    chk_fullconenat           # 检查并添加fullconenat支持
    fix_mk_def_depends        # 修复默认依赖
    add_wifi_default_set      # 添加WiFi默认设置
    update_default_lan_addr   # 更新默认LAN地址
    update_default_hostname   # 更新默认主机名
    add_network_config_script # 添加网络配置脚本
    add_bypass_router_script  # 添加旁路由设置脚本
    add_ipv6_config_script    # 添加IPv6配置脚本
    
    # 硬件和性能优化
    remove_something_nss_kmod # 移除不需要的NSS内核模块
    update_affinity_script    # 更新中断亲和性脚本
    fix_build_for_openssl     # 修复OpenSSL构建
    update_ath11k_fw          # 更新ath11k固件
    # fix_mkpkg_format_invalid  # 修复软件包格式无效问题（已注释）
    chanage_cpuusage          # 修改CPU使用率获取方式
    
    # 工具和应用更新
    update_tcping             # 更新tcping工具
    add_wg_chk                # 添加WireGuard检查脚本
    add_ax6600_led            # 添加AX6600 LED控制应用
    set_custom_task           # 设置自定义任务
    update_pw_ha_chk          # 更新PassWall的HAProxy检查
    
    # 系统配置和优化
    install_opkg_distfeeds    # 安装OPKG源配置
    update_nss_pbuf_performance # 更新NSS PBUF性能设置
    set_build_signature       # 设置构建签名
    fix_compile_vlmcsd        # 修复vlmcsd编译问题
    update_nss_diag           # 更新NSS诊断脚本
    update_menu_location      # 更新菜单位置
    fix_compile_coremark      # 修复CoreMark编译问题
    update_dnsmasq_conf       # 更新Dnsmasq配置
    # update_lucky              # 更新Lucky应用（已注释）
    
    # 最终配置和优化
    add_backup_info_to_sysupgrade # 添加系统升级时的备份信息
    optimize_smartDNS         # 优化SmartDNS配置
    update_mosdns_deconfig    # 更新MosDNS默认配置
    fix_quickstart            # 修复QuickStart应用
    update_oaf_deconfig       # 更新应用过滤器默认配置
    install_feeds             # 安装feeds
    update_script_priority    # 更新启动顺序
}

# 执行主函数，传递所有命令行参数
main "$@"
