# sb-auto

Sing-box 一键安装 / 管理脚本，支持 Vless-reality、Vmess-ws、Hysteria2、Tuic-v5、Anytls 等协议，自动签发自签/Acme 证书，集成 WARP 分流。

## VPS 专用一键脚本

快捷方式 `sb`：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh)
```

或者：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/wqnnwlkgo/sb-auto/main/sb-auto.sh)
```

> 安装完成后，直接输入 `sb` 即可再次打开管理菜单。

## 支持系统

- Ubuntu / Debian / CentOS（含基于 apt/yum/dnf 的发行版）
- Alpine（apk）
- 架构：amd64 / arm64 / armv7

## 使用

以 root 运行：

```bash
bash sb-auto.sh
```

脚本会自动安装依赖（curl、openssl、jq、iptables 等），下载 sing-box 内核，交互式设置各协议端口、UUID 与证书。

## 说明

- 运行时产生的配置、证书、密钥和节点信息（`/etc/s-box/` 下的 `*.json`、`cert.pem`、`private.key`、`*.txt`、`*.log` 等）均为敏感数据，已在 `.gitignore` 中排除，**不要**提交到仓库。
- 本仓库只应包含脚本源码本身。

## License

见 [LICENSE](LICENSE)。
