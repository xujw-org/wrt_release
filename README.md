首先安装 Linux 系统，推荐 Ubuntu LTS  

安装编译依赖  
sudo apt -y update  
sudo apt -y full-upgrade  
sudo apt install -y dos2unix libfuse-dev  
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'  

使用步骤：  
git clone https://github.com/ZqinKing/wrt_release.git  
cd wrt_relese  
  
编译京东云雅典娜(02)、亚瑟(01)、太乙(07)、AX5(JDC版):  
./build.sh jdcloud_ipq60xx_immwrt  
./build.sh jdcloud_ipq60xx_libwrt  
  
编译京东云百里:  
./build.sh jdcloud_ax6000_immwrt  
  
编译阿里云AP8220:  
./build.sh aliyun_ap8220_immwrt  
  
编译红米AX5:  
./build.sh redmi_ax5_immwrt  
  
编译红米AX6:  
./build.sh redmi_ax6_immwrt  
  
编译红米AX6000:  
./build.sh redmi_ax6000_immwrt21  
  
编译CMCC RAX3000M:  
./build.sh cmcc_rax3000m_immwrt  
  
编译N1:  
./build.sh n1_immwrt  
  
编译X64:  
./build.sh x64_immwrt  
  
编译兆能M2:  
./build.sh zn_m2_immwrt  
./build.sh zn_m2_libwrt  
  
三方插件源自：https://github.com/kenzok8/small-package.git  
  
使用OAF（应用过滤）功能前，需先完成以下操作：  
1. 打开系统设置 → 启动项 → 定位到「appfilter」  
2. 将「appfilter」当前状态**从已禁用更改为已启用**  
3. 完成配置后，点击**启动**按钮激活服务

# 新增脚本的使用方法

在 update.sh 中添加了几个实用的网络配置脚本，下面是它们的使用方法：

## 1. 网络配置脚本 (network-config)

这个脚本用于快速配置网络接口参数。

### 使用方法：
```bash
network-config [选项]
```

### 常用选项：
- `-h, --help` - 显示帮助信息
- `-i, --interface <接口>` - 指定要配置的接口 (默认: lan)
- `-a, --address <IP地址>` - 设置IP地址 (例如: 192.168.1.1)
- `-m, --mask <子网掩码>` - 设置子网掩码 (例如: 255.255.255.0 或 24)
- `-g, --gateway <网关>` - 设置默认网关
- `-d, --dns <DNS服务器>` - 设置DNS服务器 (用逗号分隔多个服务器)

### 示例：
```bash
# 将LAN接口设置为192.168.2.1，子网掩码255.255.255.0，网关192.168.2.254
network-config -i lan -a 192.168.2.1 -m 255.255.255.0 -g 192.168.2.254 -d 223.5.5.5,8.8.8.8
```

## 2. 旁路由设置脚本 (set-bypass-mode)

这个脚本用于一键将路由器设置为旁路由模式。

### 使用方法：
```bash
set-bypass-mode [选项]
```

### 常用选项：
- `-h, --help` - 显示帮助信息
- `-a, --address <IP地址>` - 设置旁路由IP地址 (例如: 192.168.1.2)
- `-g, --gateway <网关>` - 设置上级路由器IP地址 (例如: 192.168.1.1)
- `-m, --mask <子网掩码>` - 设置子网掩码 (例如: 255.255.255.0)
- `-d, --dns <DNS服务器>` - 设置DNS服务器 (用逗号分隔多个服务器)
- `-f, --firewall` - 配置防火墙规则
- `-r, --restore` - 恢复为正常路由模式

### 示例：
```bash
# 设置为旁路由模式，IP为192.168.1.2，上级路由器为192.168.1.1
set-bypass-mode -a 192.168.1.2 -g 192.168.1.1 -f

# 恢复为正常路由模式
set-bypass-mode -r
```

## 3. IPv6配置脚本 (ipv6-config)

这个脚本用于配置IPv6相关设置。

### 使用方法：
```bash
ipv6-config [选项]
```

### 常用选项：
- `-h, --help` - 显示帮助信息
- `-e, --enable` - 启用IPv6
- `-d, --disable` - 禁用IPv6
- `-m, --mode <模式>` - 设置IPv6模式 (native, relay, hybrid, passthrough)
- `-r, --router <类型>      设置路由器类型 (main, bypass)
- `-p, --prefix <前缀>` - 设置IPv6前缀 (用于relay模式)
- `-s, --server <服务器>` - 设置IPv6中继服务器 (用于relay模式)
- `-u, --upstream <地址>    设置上游路由器IPv6地址 (用于旁路由模式)

### 示例：
```bash
# 启用IPv6，使用本地模式
ipv6-config -e -m native

# 配置IPv6中继模式
ipv6-config -e -m relay -p 2001:db8::/64 -s 192.168.1.100

# 配置旁路由模式
ipv6-config -e -m native -r bypass -u fdf1:ccc4:750b::5

# 禁用IPv6
ipv6-config -d
```

## 4. 主机名修改

主机名修改是在编译时自动完成的，默认将主机名从"OpenWrt"修改为"ImmortalWrt"。如果您想在运行的系统上修改主机名，可以使用以下命令：

```bash
# 修改主机名
uci set system.@system[0].hostname='新主机名'
uci commit system
/etc/init.d/system restart
```

这些脚本在路由器系统中位于 `/usr/bin/` 目录下，可以直接在SSH终端中执行。
