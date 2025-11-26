# Caddy Reverse Proxy for Emby (One-Click Script)

一个基于 Caddy 的 Emby 反向代理一键配置脚本。自动申请 HTTPS 证书，支持真实 IP 透传。

![Shell Script](https://img.shields.io/badge/Language-Bash-green)
![License](https://img.shields.io/badge/License-MIT-blue)

## ✨ 功能特点

* **全自动安装**：自动识别系统 (Ubuntu/Debian/CentOS) 并安装最新版 Caddy。
* **交互式配置**：无需手动编辑文件，根据提示输入域名和内网 IP 即可。
* **最佳实践配置**：
    * 自动申请并续期 Let's Encrypt SSL 证书。
    * 开启 Gzip 压缩。
    * 配置 `X-Forwarded-For`，让 Emby 能看到用户的真实 IP。
* **菜单管理**：内置管理菜单，支持重置配置、重启服务和卸载。

## 🚀 快速开始

使用 root 用户在终端运行以下命令：

```bash
bash <(curl -sL [https://raw.githubusercontent.com/AiLi1337/install_caddy_emby/main/install_caddy_emby.sh](https://raw.githubusercontent.com/AiLi1337/install_caddy_emby/main/install_caddy_emby.sh))
