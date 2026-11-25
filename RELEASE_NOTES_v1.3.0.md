# sb-auto v1.3.0

本版本新增 Telegram 按 IP 段走 WARP 分流开关，对全脚本配置修改进行 `jq` 原子化重构，修复多处高危/中危 Bug，并大幅优化主菜单启动速度。

## 新功能

- **Telegram 按 IP 段走 WARP 出站**：在分流菜单（选项 5）中新增一键开关（选项 7），支持将 Telegram 官方 IPv4/IPv6 网段分流至 WARP 出站，兼顾 1.10 与 1.11+ 内核。
- **文档补充**：README 增加手动覆盖更新 `sb` 脚本的快捷命令。

## 重点重构与性能优化

- **全量 `jq` 重构 JSON 修改**：新增 `sbjq_read` / `sbjq_edit` / `sbjq_edit_all` 原子读写辅助函数，全面替换证书切换、端口修改、UUID/Path 修改、IP 优先级、WARP 账户、域名分流、Telegram 分流、Socks5 端口等处的硬编码行号 `sed` 与全局替换，杜绝行号错位和短密码误伤配置。
- **主菜单并发提速**：并发拉取脚本版本、内核版本与本机 IP 信息，合并重复请求、为所有探测补充超时控制并复用同轮缓存，单栈 VPS 不再白等另一协议超时，未监听 Socks5 端口时跳过无意义探测。

## 问题修复

- **客户端配置与分享链接**：
  - 修复 Hysteria2 使用 Acme 域名证书时错误附带空/旧自签 `pinSHA256` 导致握手失败的问题。
  - 修复 `sbox.json` 缺少 `{"action": "sniff"}` 导致 TUN 模式下 DNS 劫持失效的问题。
  - 修复 `sbox.json` 中 Hysteria2 启用端口跳跃时同时输出互斥的 `server_port` 与 `server_ports` 的问题，并移除 Vmess 非 TLS 时的多余 `utls` 字段。
  - 修复 `clmi.yaml` 中 Tuic5 自签证书误设 `disable-sni: true` 的问题，并为 `server`/`sni`/`Host` 等字段加双引号兼容纯 IPv6。
  - 修复每次刷新节点无条件覆写 `/root/ygkkkca/ca.log` 可能导致域名被清空的问题。
- **Alpine 与多系统兼容**：
  - 修复 Alpine 首次安装漏装 `curl`/`wget`/`qrencode`/`python3`/`xxd`/`ip6tables` 的问题，以及依赖标记文件使用相对路径导致跨目录重复安装的问题。
  - 修复 Argo 固定隧道 OpenRC 脚本 `command` 含子命令导致无法启动的问题，补齐 `cloudflared` 的 `armv7l` 架构映射。
  - 修复 Alpine 重复安装检测漏查 `/etc/init.d/sing-box` 与 `sb.json` 的问题；移除代码中不兼容的 `grep -P`；修正 CentOS/RHEL 误调 `apt` 与 `xxd` 包名问题。
- **安装、端口、防火墙与安全**：
  - 修复 1.10 内核手动配置端口时未给 `sb11.json` 分配 `port_an` 导致升级内核后配置损坏的问题，并增加手动端口互判重复及 `AUTO=1` 模式 NAT 冲突检测。
  - 修复内核更新未校验 HTTP 状态与解压产物导致的“假成功”，脚本自更新改为先下载校验再原子替换并移除 `--insecure`。
  - 修复 Acme 证书申请失败判断逻辑写反（`&&` -> `||`）的问题。
  - 修复 UFW 判重误跳过 `DENY` 规则、`iptables` `--comment "sb-auto"` 引号兼容、`sbnatports`/`sbnatconflict` 遗漏 IPv6 及遇非 `--dport` 规则报错等问题。
- **Telegram、订阅、GitLab 与 WARP-plus-Socks5**：
  - 修复 Telegram 推送 `sbox.json` 第 4 段截断丢失末尾 JSON 行的问题，并移除易触发 400 错误的 `parse_mode=HTML`。
  - 修复本地 IP 订阅 `subtoken` 缺少路径字符校验导致的越界删除风险，复用端口校验并自动放行防火墙端口。
  - 修复 GitLab 订阅污染宿主机 `git config --global` 与 `expect interact` 挂起问题。
  - 修复 WARP-plus-Socks5 局部函数覆盖全局 `unins()`、开机自启将重定向当作参数以及 Alpine 漏 `&` 阻塞启动的问题。
  - 修复 1.11+ 分流展示索引错位及 Socks5 未启动时已配置分流域名被误隐藏的问题。

## 升级方法

已安装的 VPS：运行 `sb`，选 **7** 更新脚本（或手动执行 `curl -L -o /usr/bin/sb https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh && chmod +x /usr/bin/sb`），再选 **9** 刷新节点配置与订阅。
