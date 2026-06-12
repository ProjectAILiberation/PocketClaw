# Changelog

All notable changes to PocketClaw will be documented in this file.

## [1.4.0] - 2026-06-12

### 升级 OpenClaw 2026.3.13 → 2026.6.5（已用官方 `openclaw config validate` 实测兼容）
- Dockerfile：`openclaw` 版本钉死为 `2026.6.5`（不再 `@latest` 浮动），`clawhub` 钉死 `0.21.0`；
  基础镜像升级到满足 `node>=22.19.0` 的 `node:22-slim` 并按 **digest 钉死**（可复现）。
- 配置生成（entrypoint.sh）适配新版 schema：
  - `models.providers.*.models` 由字符串数组改为 `[{id,name}]` 对象（旧形状会被新版拒绝、网关拒启动）。
  - Signal 频道字段 `number` → `account`；Google Chat `serviceAccountKeyFile` → `serviceAccountFile`（移除已失效的 `spaces`）；Matrix `homeserverUrl` → `homeserver`。
  - BlueBubbles、Zalo 频道在新版 schema 已移除/变更，暂不自动生成（配置了会明确提示跳过）。
- 重写 `gateway-patch.py`：上游已把 HTTP handler 从 `gateway-cli-*.js` 迁到 `server.impl-*.js`
  并改为 `requestStages` 派发架构。新补丁按派发点注入自定义路由，含注入后自检；
  Dockerfile 不再 `2>/dev/null || true` 吞错——注入失败会让构建**硬失败**，附构建期冒烟自检。
- entrypoint.sh 启动前运行 `openclaw config validate`，配置不兼容时给出明确错误并中止（持久防线）。

### 安全加固（依据一次深度审计）
- **更新链路强制验签（修复零验证 RCE）**：`_update.sh` / `update.bat` / `install-update.sh` 在安装前
  用**钉死在仓库内**的公钥（`config/release-signing.pub`）验证更新包 Ed25519 签名，fail-closed；
  `sign-release.sh` 移除"无签名即放行""从包内读公钥"等绕过点；下载地址加 HTTPS + 主机白名单。
  （维护者需一次性 `sign-release.sh keygen` 并提交公钥后，签名更新才会启用——见 `config/release-signing.pub.example`。）
- **移除 `docker pull pocketclaw/pocketclaw:latest` 抢注快速路径**，一律本地按钉死版本构建；
  修正指向非本项目命名空间的备用源为 `tinqiao-oss/PocketClaw`。
- **网关默认仅绑定 `127.0.0.1`**（原为 `0.0.0.0` 全网卡暴露）；手机访问需用户显式设 `BIND_IP=0.0.0.0`。
- **所有 IM 频道强制发送方白名单**（`<CHAN>_ALLOW_FROM` + `dmPolicy:allowlist`），未配白名单的频道拒绝接入，
  关闭"互联网陌生人私聊全权限 Agent"通道。
- **移动端 WebUI**：修复裸 URL 自动链接导致的存储型 XSS；执行审批由"自动批准全部"改为**人在回路确认**。
- **凭据卫生**：`.gitignore` 纳入 `.provider`/`.gateway_token`/`.host_ip`/`.bound_providers`；
  已提交的运行时凭据 `git rm --cached` 取消跟踪；`build_zip.py` 排除 `secrets/`、`.provider`、`*.key/*.pem/*.encrypted`。
- **跨平台加密一致性**：Windows 全部加密路径 PBKDF2 迭代 100000 → **600000**，解密路径先试 600K 再回退 100K，
  修复"macOS 加密的 U 盘在 Windows 无法解密"。
- **Windows 网关 token** 由 8 位非加密随机改为 **32 位 CSPRNG**（与文档承诺一致）。
- 提示词/技能加固：`notes` 标题做路径穿越清洗；`skill-check` 改扫真正生效的 `config/workspace/skills`；
  `reminders` 标注 heartbeat 不可信数据、禁止当指令执行；`AGENTS.md` 移除"读取并明文回显 gateway token"的自相矛盾指引。
- `start.sh` 不再静默改写宿主机全局 `daemon.json`，改为征得用户同意 + 备份原文件。

## [1.3.5] - 2026-03-20

### Changed
- OpenClaw 升级到 2026.3.13（release tag: `v2026.3.13-1`，npm 版本仍为 `2026.3.13`）
- 同步上游 2026.3.11 / 2026.3.12 / 2026.3.13 的关键修复（含安全与稳定性更新）

### Fixed
- 修复与 OpenClaw 2026.3.13 严格配置校验的兼容问题：移除 `gateway.controlUi._comment` 非法键
- 修复新版依赖拉取兼容问题：完善 git `ssh://git@github.com` → HTTPS 改写规则，避免无 SSH 密钥环境构建失败
- 更新 `docker-compose.yml` 中 OpenClaw 内置健康检查注释版本到 2026.3.13

## [1.3.4] - 2026-03-11

### Added
- 新增 docs/SECURITY.md 安全白皮书（14 节，涵盖威胁模型、网络隔离、凭据保护等）
- 使用指南新增安全注意事项章节
- README 新增安全文档链接

### Fixed
- 修复 start.bat GBK 编码损坏导致的乱码（从 git 历史恢复 + 重新编码）

### Upstream Contributions
- 提交 PR #42869: Docker 引擎启动超时守卫（docker_is_ready 函数）
- 提交 PR #42872: .env 文件 BOM/CRLF 自动清理（sanitize_env_file 函数）

## [1.3.3] - 2026-03-11

### Fixed
- 修复国内无 VPN 用户首次构建镜像卡住 1 小时以上的问题
- Dockerfile: pip 添加阿里云镜像源加速
- Dockerfile: npm 不再优先尝试官方源（直接用淘宝镜像）
- Dockerfile: apt 镜像源替换逻辑更健壮（区分 DEB822/传统格式）
- 构建流程: 预拉基础镜像增加 120 秒超时 + 阿里云容器镜像兜底
- 预构建镜像拉取增加 60 秒超时保护
- Docker 镜像加速器列表新增腾讯云镜像源

### Security
- setup.html: innerHTML → DOM API 防 XSS + CSP 头
- mobile.html: renderMd 链接 XSS 加固（URL 构造器 + 属性转义）
- gateway-patch.py: 路径遍历防护 + 可疑请求日志
- Dockerfile: chmod a+w → u+w 最小权限
- docker-compose.yml: 端口绑定可配置 BIND_IP 环境变量
- doctor.sh: echo $VAR → printf 防变量注入
- start.sh: brew shellenv 安全改进
- build_zip.py: 文件读取异常处理
- Docker 基础镜像版本锁定 node:22.16-slim

## [1.3.2] - 2026-03-09

### Added
- 网站添加 ICP 备案号（京ICP备2026010038号-1）
- 网站新增 iFlow 心流 API Key 获取教程（放在智谱教程之前）
- PocketClaw.bat 和 .command 新增 [7] 检查更新菜单项

### Changed
- 版本检查 API 从腾讯 COS 迁移至自有服务器（pocketclaw.cn/downloads/version.json）
- 版本更新从启动时自动检查改为菜单手动检查
- 重写 update.bat 为完整版本检查+下载安装逻辑
- 网站 hero badges 移除 emoji 图标，仅保留文字

### Removed
- start.sh 和 start.bat 中的自动版本检查块
- version.json 中的 cos_url 字段（不再同步腾讯 COS）

## [1.3.1] - 2026-03-06

### Fixed
- 修复手机扫码页面 Internal Server Error（Dockerfile 中 mobile.html 复制后未 chown 给 node 用户）
- macOS 控制面板状态显示优化：地址始终带 Token、新增手机访问地址和模型健康状态
- Docker 幽影容器防护：docker run 失败时自动用备用容器名重试

## [1.2.4] - 2026-03-04

### Security
- Gateway: 移除 allowedOrigins 中的 `"null"` 项，添加安全配置说明注释
- 修复 mobile.html Markdown 渲染器 XSS 漏洞（过滤 javascript: 等危险协议）
- 限制调试用全局变量仅在开发模式下暴露

### Improved
- 增强 Markdown 渲染：新增标题(h1-h4)、表格、删除线、水平线、代码块保护
- 聊天记录改用 JSON 结构化存储（替代 raw innerHTML，上限 200 条）
- TTS 文本截断阈值提取为可配置常量
- 新增 .editorconfig 统一编辑器行为
- 新增 CHANGELOG.md 版本变更记录

### Fixed
- 修复 landing page 下载追踪代码中版本号不一致的问题

## [1.2.3] - 2026-03-03

### Fixed
- 手机页面完整修复：AI 回复显示、聊天记录持久化、页面切换自动重连
- 修复 `catch {}` ES2019 语法兼容性问题（改为 `catch(e) {}`）
- 修复 sessionKey 匹配逻辑（改用 indexOf 包含匹配）
- 修复 scopes 配置（`[]` → `['operator.admin']`）
- 修复 CSP 阻止 mobile.html 加载的问题
- 修复 Windows 版本检查 TLS 问题

## [1.2.2] - 2026-03-03

### Fixed
- Windows 版本检查 TLS 修复
- Docker 等待计时器修复
- 移除桌面语音按钮
- 手机页面 WebSocket 连接修复

## [1.2.0] - 2026-03-03

### Added
- Docker 智能构建跳过（文件指纹比对，秒级二次启动）
- 手机专属界面 + QR 码扫码访问
- Colima 兼容支持

### Fixed
- CSP 安全头修复
- 启动脚本稳定性增强
- 移除浏览器自动弹出

## [1.1.2] - 2026-03-02

### Added
- 手机主屏幕 PWA 支持
- Windows 防火墙自动配置

### Fixed
- 浏览器配置修复
- URL 路径修正
- 弃用 API 替换

## [1.1.1] - 2026-03-02

### Added
- OpenClaw 升级至 2026.3.1
- Chromium 无头浏览器集成
- Docker 健康检查
- Skills 持久化存储
- 局域网访问支持

### Improved
- Windows 启动优化

## [1.1.0] - 2026-03-01

### Added
- 10 种聊天频道支持 (Telegram/Discord/Slack/WhatsApp/Signal 等)
- 长期记忆系统
- AI 身份持久化

### Improved
- macOS/Windows 双系统完美适配

## [1.0.3] - 2026-02-27

### Added
- 首个公开版本
- GLM-4.7-Flash 免费模型默认集成
- AES-256-CBC 加密存储
- 全自动环境安装 (Docker/WSL2/镜像加速)
- 中文交互界面
