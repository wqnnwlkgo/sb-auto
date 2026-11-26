# sb-auto v1.4.1

本版本重点修复了历史残留 UDP NAT（尤其是 `ip6tables -t nat PREROUTING`）转发规则劫持新安装 Hysteria2 / TUIC5 主端口导致连接报 `connection refused` 的问题，并完善了端口跳跃规则的标记、去重与清理机制。

## 问题修复与优化

- **修复 `AUTO=1` 自动安装模式绕过 NAT 冲突检测**：
  - 安装阶段在选端口前自动调用 `sbnatprune()` 清理失效的孤儿 UDP 转发规则。
  - `AUTO=1` 随机选取 `port_hy2` 与 `port_tu` 时加入 `sbnatconflict` 校验；若默认跳跃段（`50000-60000` / `40000-49999`）被其他存活服务的 NAT 规则占满，自动回退到 `10000-65535` 中无冲突端口，确保主端口不被劫持。
- **新增失效孤儿 NAT 规则自动清理（`sbnatprune`）**：
  - 扫描 `iptables` / `ip6tables` `nat PREROUTING` 链中指向本机未监听 UDP 端口的纯端口转发规则并自动清理保存。
  - 严格跳过当前存活的 UDP 监听端口、当前 `sb.json` 中配置的协议主端口，以及指定了其他目标 IP 的跨机 DNAT 规则，防止误删。
- **完善 NAT 规则标记、去重与清理**：
  - `sbnatadd()` 添加规则前先执行 `-C` 去重，并优先附加 `-m comment --comment sb-auto` 标记（内核不支持 `comment` 模块时自动回退无注释规则），避免重复规则堆积。
  - `sbnatclr()` 修复正则以兼容 `--dport` 与 `-j` 之间存在 `-m comment` 等扩展参数。
  - `sbnatdel()` 卸载时同步清理所有带有 `sb-auto` 注释标记的 `PREROUTING` NAT 规则，不再局限于硬编码端口段。

## 升级方法

已安装的 VPS：运行 `sb`，选 **7** 更新脚本（或手动执行 `curl -L -o /usr/bin/sb https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh && chmod +x /usr/bin/sb`）。
