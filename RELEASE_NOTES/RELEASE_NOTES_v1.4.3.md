# sb-auto v1.4.3

本版本新增内核 UDP 默认与最大缓冲区自动调优机制，解决 Hysteria2 启用 `salamander` 混淆时因无法自动扩容 socket 缓冲区而被迫退回系统极小默认值（如 64 KB / 208 KB），从而引发大量内核丢包、高 CPU 占用与代理限速的问题。

## 优化内容

- **新增内核 UDP 缓冲区自动优化（`sb_tune_udp_buf`）**：
  - **按内存自适应目标值**：根据宿主机 `/proc/meminfo` 总内存自动计算安全阈值（≥ 1 GB 设默认 8 MB / 最大 16 MB；512 MB ~ 1 GB 设默认 4 MB / 最大 16 MB；< 512 MB 设默认 2 MB / 最大 8 MB），避免低配小内存机型占用过多内存。
  - **只升不降与幂等执行**：若宿主机原有 `rmem_default` / `wmem_default` / `rmem_max` / `wmem_max` 已高于目标值则保留原配置；已达标且持久化文件存在时直接跳过。
  - **防覆盖持久化**：写入 `/etc/sysctl.d/zz-sb-auto-udp.conf`（`zz-` 前缀确保字典序晚于 `local.conf`、`99-*.conf` 加载），并自动检查提升 `/etc/sysctl.conf` 中显式写死的更低值，防止系统重启后被 `sysctl --system` 覆写；通过 `sysctl -p` 精准加载（无 `sysctl` 时回退直写 `/proc/sys`）。
  - **受限环境安全跳过**：检测到 OpenVZ / LXC 容器或 `/proc/sys/net/core/{r,w}mem_default` 不可写时自动跳过，不中断安装流程。
- **全生命周期接入**：
  - 首次安装启动服务（`sbservice()`）与服务重启（`restartsb()`）前自动调用，确保新老节点均能生效。
  - 卸载脚本（`unins()`）时同步清理 `/etc/sysctl.d/zz-sb-auto-udp.conf`。

## 升级方法

已安装的 VPS：运行 `sb`，选 **7** 更新脚本（或手动执行 `curl -L -o /usr/bin/sb https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh && chmod +x /usr/bin/sb`），随后选 **6 -> 1** 重启 Sing-box 即可使内核缓冲区优化生效。
