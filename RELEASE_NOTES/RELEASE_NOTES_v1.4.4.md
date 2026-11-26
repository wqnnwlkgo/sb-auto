# sb-auto v1.4.4

本版本针对服务端资源开销与 Hysteria2 实际线路表现进行默认参数调优，降低高频日志写入与 Brutal 过度超发带来的 CPU 和流量消耗。

## 优化内容

- **服务端默认日志级别调整为 `warn`**：
  - 将 `sb10.json` 与 `sb11.json` 配置模板中的 `log.level` 从 `"info"` 改为 `"warn"`，过滤逐条连接的常规日志刷屏，同时保留告警与错误信息以便通过菜单 `10` 排查故障。
- **Hysteria2 默认带宽调整为 `30 / 80 Mbps`**：
  - 将客户端默认写入的上行/下行带宽由 `50 / 200 Mbps` 调整为 **上行 30 Mbps、下行 80 Mbps**，减少普通高丢包线路下 Brutal 拥塞控制盲目超发造成的重传、CPU 飙高及运营商 UDP QoS 限流风险。
  - 仍支持通过 `/etc/s-box/hy2_bw.txt`（格式：`上行 下行`，如 `echo "50 150" > /etc/s-box/hy2_bw.txt`）按需自定义覆盖，修改后运行 `sb` 选 `9` 刷新即可生效。

## 升级方法

已安装的 VPS：运行 `sb`，选 **7** 更新脚本（或手动执行 `curl -L -o /usr/bin/sb https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh && chmod +x /usr/bin/sb`），再选 **9** 刷新节点配置即可应用新的默认带宽（现有 `/etc/s-box/sb.json` 的日志级别如需同步降低，可手动将 `"level": "info"` 改为 `"level": "warn"` 后重启 Sing-box）。
