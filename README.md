# Caddy反代EMBY一键脚本

![Language](https://img.shields.io/badge/Language-Bash-green.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Version](https://img.shields.io/badge/Version-V4.0-orange.svg)

这是一个专为 **Emby** 设计的 Caddy 反向代理一键配置脚本。
支持自动申请 HTTPS 证书、自动配置开机自启、支持反代远程 HTTPS 服务器，并内置了端口冲突自动处理功能。

## 🚀 快速开始 (一键安装)

**使用 Root 用户**在终端运行以下命令即可：

```bash
bash <(curl -sL [https://raw.githubusercontent.com/AiLi1337/install_caddy_emby/main/install_caddy_emby.sh](https://raw.githubusercontent.com/AiLi1337/install_caddy_emby/main/install_caddy_emby.sh))
```
## ✨ 核心功能 (V4 更新)

  * **⚡️ 极速配置**：自动识别系统 (Debian/Ubuntu/CentOS) 并安装最新版 Caddy。
  * **🔄 循环菜单**：操作完不退出，方便进行多项设置（安装 -\> 检查端口 -\> 配置）。
  * **🛠 端口自动修复**：一键检测并强制清理占用 80/443 端口的 Nginx/Apache 进程，解决 Caddy 启动失败问题。
  * **🔒 完美 HTTPS 支持**：
      * 自动申请并续期 Let's Encrypt SSL 证书。
      * **支持反代 HTTPS 后端**：自动修正 Host 头，完美反代远程 Emby 服务器 (解决 404/403 错误)。
  * **🚀 性能优化**：
      * 开启 Gzip 压缩。
      * 透传真实 IP (`X-Forwarded-For`)，方便 Emby 识别客户端。
      * 自动配置开机自启。

## 📖 使用指南

### 1\. 运行脚本

输入上述一键命令后，您将看到如下菜单：

```text
#################################################
#    Caddy + Emby 一键反代脚本 (V4 Loop)        #
#################################################
 1. 安装环境 & Caddy
 2. 配置反代 (输入域名/IP)
 3. 停止 Caddy
 4. 重启 Caddy
 5. 卸载 Caddy
-------------------------------------------------
 6. 查询 443/80 端口占用
 7. 暴力处理端口占用 (修复启动失败)
-------------------------------------------------
 0. 退出脚本
```
### 2\. 推荐操作步骤

1.  **安装**：输入 `1` 安装 Caddy。
2.  **清理端口**（可选但推荐）：如果您的服务器安装过 Nginx，建议输入 `7` 确保端口干净。
3.  **配置**：输入 `2`，按照提示输入您的域名和 Emby 地址。
      * *域名示例*：`emby.yourdomain.com` (请确保已解析到本机 IP)
      * *后端示例*：`127.0.0.1:8096` 或 `https://remote-emby.com:443`

## ❓ 常见问题

**Q: 启动失败，提示 "bind: address already in use"？**
A: 这是因为 80 或 443 端口被 Nginx/Apache 占用了。请在脚本菜单中选择 **[7] 暴力处理端口占用**，然后重新选择 **[4] 重启 Caddy**。

**Q: 反代后 Emby 无法播放或 404？**
A: 脚本已自动处理 Host 头。请确保您输入的后端地址正确。如果是远程 HTTPS 后端，请务必带上 `https://` 前缀。

**Q: 如何查看运行日志？**
A: 使用命令 `systemctl status caddy -l` 或 `journalctl -u caddy -f`。
