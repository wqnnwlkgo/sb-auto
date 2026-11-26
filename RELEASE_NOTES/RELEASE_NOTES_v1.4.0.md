# sb-auto v1.4.0

本版本将双栈 VPS 的节点与客户端配置输出全面升级为**同时输出 IPv4 与 IPv6 配置**，并集中修复了多处 IPv6 与纯 IPv6 环境下的兼容性 Bug。

## 新功能

- **双栈全量配置输出**：
  - `ipuuid()`（菜单选项 15）不再要求双栈 VPS 在 IPv4/IPv6 之间二选一，直接刷新并分别持久化 `/etc/s-box/server_ipv4.log` 与 `/etc/s-box/server_ipv6.log`（兼容维护旧版 `server_ip.log` / `server_ipcl.log`）。
  - 双栈 VPS 下，直连 VPS IP 的协议（VLESS-Reality，以及未启用 TLS/无自定义优选时的 VMess-WS、自签证书时的 Hysteria2 / TUIC5 / AnyTLS）自动同时输出 `-v4` 和 `-v6` 两条分享链接与独立二维码，并全部写入聚合订阅 `jhsub.txt`。
  - 重构 `sb_client()`，生成的 `sbox.json` 与 `clmi.yaml` 自动展开双栈节点并同步加入所有代理分组；单栈 VPS 仅输出可用协议栈节点，不生成空 IP 节点。
  - 本地 IP 订阅状态展示同步输出 IPv4 与 IPv6 订阅地址。

## 问题修复

- **客户端配置与分享链接（IPv6 兼容）**：
  - 修复 `sbox.json` 中 AnyTLS 节点 `server` 字段误带方括号 `[...]` 导致客户端无法连接的问题。
  - 修复 `vmess://` 分享链接 JSON 中 `"add"` 字段在 IPv6 下误带方括号的问题，并对用户自定义优选 IPv6 自动剥离方括号。
  - 修复 `clmi.yaml` 中 Argo 节点 `server`/`servername`/`Host` 缺少双引号，在填入 IPv6 优选地址时引发 YAML 语法错误的问题。
- **纯 IPv6 环境与防火墙**：
  - 修复 WARP-plus-Socks5（`inssbwpph`）在纯 IPv6 VPS 上仍硬编码 IPv4 Endpoint `162.159.192.1:2408` 导致连接失败的问题，无 IPv4 时自动切换为 `[2606:4700:d0::a29f:c001]:2408`。
  - 修复 `close()`（防火墙选项 3）遗漏清理 `ip6tables`、CentOS/RHEL 依赖安装遗漏启用 `ip6tables` 服务，以及 `sbfwsave()`/`sbnatdel()` 遗漏 `service ip6tables save` 的问题。
  - 新增 `sbnatadd()` 优先使用 `REDIRECT --to-ports`（失败回退 `DNAT`），并让端口跳跃读取、冲突检测、持久化与清理全面兼容 `REDIRECT` 与 `DNAT`（含 `[::]:port`）。
  - 修复本地 IP 订阅 `busybox httpd` 默认仅监听 IPv4 的问题，优先绑定 `[::]:port` 并在不支持 IPv6 时自动回退，同步更新开机自启脚本与进程检测正则。
- **稳定性与边界修复**：
  - 修复 `warpwg()` 覆盖全局变量 `$v6` 导致本机公网 IPv6 被污染的问题，改用独立变量 `warp_v6`；优化 `changewg()` 对 IPv6 对端地址的 `[IPv6]:port` 展示格式。
  - 新增 `is_valid_ipv4()`、`is_valid_ipv6()`、`fmt_host_port()` 与 `ensure_nat64()`，清洗探测结果避免错误页污染配置，并在纯 IPv6 VPS 首次装依赖前提前配置 NAT64。

## 升级方法

已安装的 VPS：运行 `sb`，选 **7** 更新脚本（或手动执行 `curl -L -o /usr/bin/sb https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh && chmod +x /usr/bin/sb`），再选 **15** 刷新双栈 IP 并重新生成配置与订阅。
