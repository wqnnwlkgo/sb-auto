# sb-auto v1.4.2

本版本对脚本进行了全面代码审计与集中加固，修复了多项高危/中危 Bug、安全隐患与边界兼容问题，同时优化了端口分配、版本管理、Argo 隧道、本地订阅与菜单交互体验。

## 安全加固

- **消除 NAT 规则删除中的 `eval` 注入风险**：新增 `sbnat_del_rule()`（优先使用 `python3` 的 `shlex.split` + `subprocess.run`，无 `python3` 时拦截危险元字符并以纯 Bash 引号状态机安全拆分参数数组），替换全脚本 6 处 `eval "$t -t nat -D ..."`。
- **加固 `sbnatprune()` 防止误删规则**：执行前校验 `ss` 命令存在且 `ss -lun` 成功返回，改为自适应匹配监听端口列，彻底避免 `ss` 缺失或列号差异导致误删宿主机 UDP NAT 规则。
- **加固敏感目录与 JSON 读写**：`/etc/s-box` 创建时统一设置 `chmod 700`；`sbjq_read()` / `sbjq_edit()` 优先直接解析标准 JSON，仅失败时回退剥离整行 `//` 注释，避免误截断字符串值中的 URL 或 ` //`。

## 核心问题修复

- **Sing-box 内核兼容与配置模板**：
  - 修复 `sb10.json` 与 `sb11.json` 兜底路由中 `"network": "udp,tcp"` 语法不合规问题，改为标准数组 `"network": ["udp", "tcp"]`。
  - 新增 `sb_ver_supports_anytls()`（判定 `>= 1.12`）与 `sb_apply_config()`，修复在 sing-box `1.11.x` 下误启 `anytls-sb` 导致崩溃的问题；切换内核后增加 `sing-box check` 校验并调用 `sbfwre` 同步放行端口。
  - 修复 Alpine OpenRC 服务 `/etc/init.d/sing-box` 缺少 `directory="/root"` 导致 1.10 内核找不到 `geoip.db`/`geosite.db` 的问题；仅在 1.10 内核按需下载数据库文件并添加超时重试。
- **端口分配与依赖安装**：
  - 修复 `insport()` 在 CDN 标准端口全被占用时可能陷入无限死循环的问题，自动回退随机可用端口；所有随机端口循环均设尝试次数上限。
  - 修复非 `AUTO=1` 模式随机选口时 `port_hy2`/`port_tu` 绕过 `sbnatconflict` 检查的问题，并将 `AUTO=1` 选口逻辑整合进 `insport()`，消除端口重复覆写与输出不一致。
  - 修复 CentOS/Rocky/AlmaLinux 依赖安装阶段执行 `yum update -y` / `dnf update -y` 触发全系统软件包升级的问题，改为 `makecache`；补充检测并自动安装缺失的 `ss`（`iproute2`/`iproute`）。
- **节点分享链接与订阅/推送**：
  - 新增 `vmess_uri()` 使用 `jq` 构造严格转义的 JSON，并用 `base64 | tr -d '\n'` 替代不兼容 BusyBox 的 `base64 -w 0`。
  - 修复 `resan()` 链接多余 `?&sni=` -> `?sni=`；`reshy2()`/`restu5()`/`resan()` 非直连分支统一调用 `fmt_host_port` 兼容 Acme IPv6 证书；`reshy2()` 自签指纹提取失败时自动回退 `insecure=1`；修正提示文案中的过期菜单号 `3-8-*` -> `3-9-*`。
  - 修复 `ipsub()` 本地订阅在未先安装就选 2/3 时出现空端口或暴露根目录的问题；换端口前先优雅停止 `httpd.*websbox`；启动与开机自启统一加 `nohup ... </dev/null` 并校验进程实际存活。
  - 修复 TG 推送（`sbtg.sh`）仅以最后一条消息状态判定成败的问题，改为逐条累计统计成功/失败/超时条数。
- **Argo 隧道、参数校验与交互体验**：
  - 新增 `argo_tmp_domain()` 正则提取最新临时域名，替换脆弱的 `awk 'NR==2'`；`cfargoym()` 改用 `systemctl` + `/run/systemd/system` 替代 `pidof systemd` 并修复多 PID 清理问题；`cfargo()` 验证失败时立即清理临时进程，移除过宽的 `cron_update 'url http'` 规则。
  - 修复 `changeuuid()` 缺少标准 UUID 校验、`changewg()` 回车跳过 Reserved 丢弃新账户 `$res`、`inssbwpph()` 国家码未转大写校验且失败未回滚 socks 端口、`fports()`/`fport()` 无法取消返回等问题。
  - 新增 `return_menu()` 替代裸调外部 `sb` 命令返回主菜单，避免本地运行报错与子进程层层嵌套；`stclre()` 补充 `0` 返回；统一安装状态提示与 `sb_write_version()` 版本号写入校验。
  - 优化容器环境 BBR 检测（`ping` 增加 `-W 1` 超时）、`run_without_warp()` 按原运行状态恢复 WARP、`v4orv6()` 并行探测、`write_nat64_resolv()` 保护系统 DNS 软链及 GitLab/CentOS 换源子 shell 隔离。

## 文档与仓库整理

- 归档历史 `RELEASE_NOTES_v1.2.0.md`、`RELEASE_NOTES_v1.2.1.md`、`RELEASE_NOTES_v1.3.0.md` 至 `RELEASE_NOTES/` 目录。
- 更新 `README.md`，注明 `sbox.json` 需搭配 sing-box 1.14+ 客户端使用，并清理不存在的 `LICENSE` 死链。

## 升级方法

已安装的 VPS：运行 `sb`，选 **7** 更新脚本（或手动执行 `curl -L -o /usr/bin/sb https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh && chmod +x /usr/bin/sb`）。
