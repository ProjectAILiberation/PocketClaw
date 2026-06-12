# PocketClaw 待修复问题清单（截至 v1.4.0）

> 本文件记录一次深度安全/维护审计后，**v1.4.0 尚未修复、但值得后续处理**的问题。
> 已在 v1.4.0 修复的内容见 `CHANGELOG.md`。
> 每条给出：严重度、涉及文件、影响、建议修法。优先级见末尾「建议处理顺序」。
> 生成日期：2026-06-12。

---

## ⚠️ 0. 最紧急（限时 / 由本次升级引入）

### 0.1 Anthropic 模型清单已退役 / 3 天内退役（providers.json）
- **严重度**：High（功能将在数日内损坏）
- **文件**：`config/providers.json`
- **影响**：以 2026-06-12 核对：`claude-3-5-haiku-20241022` 已于 2026-02 退役，调用返回 404；`claude-sonnet-4-20250514`、`claude-opus-4-20250514` 均 deprecated，**退役日 2026-06-15（仅剩 3 天）**，而 `anthropic.defaultModel` 正是即将退役的 Sonnet 4。选用 Anthropic 通道的用户会在数日内遇到模型不可用。
- **建议修法**：更新为当前在售 ID（`claude-haiku-4-5`、`claude-sonnet-4-6`、`claude-opus-4-8`），`defaultModel` 指向 `claude-sonnet-4-6`；同时核对各厂商 `contextWindow/maxTokens`。其余厂商（OpenAI/Gemini/DeepSeek/Kimi/GLM 等）的默认模型也建议趁这次一并刷新。

> 说明：本清单其余条目按主题排列；模型清单刷新因有硬截止日期单列在最前。

---

## 1. 网络暴露与网关鉴权（仍开放）

### 1.1 `allowedOrigins` 含通配符 `"*"`（静态配置 + 运行时生成都有）
- **严重度**：Medium-High
- **文件**：`config/openclaw.json`、`scripts/entrypoint.sh`（生成配置时 L265 同样写 `"*"`）
- **影响**：通配符使前面的白名单形同虚设，等于关闭 CORS/Origin 保护。用户浏览恶意网页时该页面可对 `http://localhost:18789` 控制面板发起跨源 WebSocket（CSWSH）/跨源请求（配合 DNS-rebinding），结合 `allowInsecureAuth` + 关闭设备审批，可从网页侧操控本地 agent。v1.4.0 已把 compose 端口默认绑回 127.0.0.1，但 origin 通配符仍在。
- **建议修法**：删掉 `"*"`，仅保留 `127.0.0.1:18789` 与 `localhost:18789`（需要手机访问时由 entrypoint 按实际 `host_ip` 动态加白名单，而非通配）。

### 1.2 仓库内 `config/openclaw.json` 仍含弱默认（token `"pocketclaw"` + 关设备审批 + `"*"`）
- **严重度**：Medium
- **文件**：`config/openclaw.json`
- **影响**：这是提交进公开仓库（54 星）的配置，token 明文是人人皆知的 `pocketclaw`，且 `dangerouslyDisableDeviceAuth:true`、`allowedOrigins` 含 `"*"`、`bind:lan`。entrypoint 运行时会覆盖，但只要这份静态文件在任何路径被直接加载（手动 `docker run`、被当默认值照搬），同网段任何看过公开仓库的人都能用 `pocketclaw` 接管网关。
- **建议修法**：改名为 `openclaw.example.json`，token 写成显眼占位（如 `REPLACE_ME_RANDOM`），删 `"*"`，默认不关设备审批；entrypoint 启动时校验并拒绝 `token=="pocketclaw"`。

### 1.3 `.env.example` 把 `GATEWAY_AUTH_PASSWORD=pocketclaw` 写成"真实密码"
- **严重度**：Medium
- **文件**：`.env.example`、`scripts/setup-env.sh`/`.bat`
- **影响**：注释没提 sentinel 机制。有安全意识的用户会把它改成自己的弱口令——结果反而关闭了随机 token 生成，把人类可记忆的弱口令挂在局域网端口上，可在线爆破。
- **建议修法**：改为 `GATEWAY_AUTH_PASSWORD=`（留空）并注释"留空 = 每次启动自动生成高强度随机 token（推荐）"；entrypoint 把空值也明确纳入自动生成分支。

### 1.4 局域网传输无加密：token 经明文 `ws://` 传输；`_https.sh` 是死代码
- **严重度**：Medium
- **文件**：`scripts/_https.sh`、`scripts/start.sh`、`docs/SECURITY.md`、`config/mobile.html`
- **影响**：U 盘走局域网 HTTP，WebSocket 退化为明文 `ws://`，`connect` 里的 `auth.token` 及所有聊天内容在 LAN 上明文传输，同网段抓包即得 token（→operator.admin）。而文档宣称的"用 mkcert 给 LAN 加 HTTPS"——`_https.sh` **从未被 start.sh source/调用**，是空操作，用户以为开了 TLS 实则没有。
- **建议修法**：要么在 start.sh 检测 LAN 访问时真正 source 并调用 `_https.sh` 的 `setup_https_certs`，把证书接入网关 TLS、URL 改 `https://`/`wss://`；要么删除死代码并修正 README/SECURITY.md。

### 1.5 mobile.html 缺 CSP，且调试面板会明文显示含 token 的 URL
- **严重度**：Medium
- **文件**：`config/mobile.html`
- **影响**：① 唯一渲染不可信 AI 内容的页面 mobile.html **没有任何 CSP**（反倒几乎不渲染不可信内容的 setup.html 配了 CSP，投放用反了地方）；② token 放在 URL `#token=` 片段，代码特意把显示脱敏成前 3 位，却在调试日志（L584-585、L1391）用 `location.href`/`location.hash` 打印**完整 token**，连接不稳到第 5 次重连时面板自动展开，旁观者可肩窥抄走 token。
- **建议修法**：给 mobile.html 加 CSP（`default-src 'self'; connect-src 'self' ws: wss:; object-src 'none'; base-uri 'none'`）并尽量去掉内联 `onclick` 以便启用不带 `'unsafe-inline'` 的 `script-src`；调试日志一律对 token 打码、不打印原始 href/hash；页面读入 token 后立刻 `history.replaceState` 清除 URL 片段。

### 1.6 mobile.html 前端以 `operator.admin` 连接（scope 未降权）
- **严重度**：Medium（v1.4.0 已移除"自动批准全部"，此项为残留）
- **文件**：`config/mobile.html`
- **影响**：前端申请的是最高 `operator.admin` scope。v1.4.0 已把"自动批准所有 exec"改为人在回路确认，大幅缓解；但 scope 本身仍是 admin。
- **建议修法**：降到完成聊天所需的最小 scope（需在真实 gateway + 浏览器环境测试，确认降权后 WebChat 仍能正常收发，避免连不上）。

---

## 2. 无头浏览器沙箱（仍开放）

### 2.1 Chromium 默认 `--no-sandbox` / `noSandbox:true`，且用于浏览任意网页
- **严重度**：Medium
- **文件**：`config/openclaw.json`、`Dockerfile.custom`、`config/workspace/AGENTS.md`
- **影响**：AI 会按指令打开搜索结果/用户给的任意 URL（不可信外部内容），`noSandbox` 移除了 Chromium 渲染进程沙箱。命中一个渲染器漏洞的恶意页面即可在容器内执行代码，读取 bind-mount 进来的 `credentials`/`sessions`（API key 与会话）。容器层的 `cap_drop`/non-root 能挡住进一步逃逸到宿主，但容器内的密钥已足以被洗劫。
- **建议修法**：尽量恢复沙箱（在 compose 里为浏览器单独授予 user-namespace 或合适的 seccomp，而非全局 `--no-sandbox`）；若环境确实不支持，则把浏览器限制为白名单域名、并把凭据目录改为浏览器进程不可读；至少在文档标注此风险。

---

## 3. 供应链与更新（部分开放）

> v1.4.0 已修：自动更新强制验签（`_update.sh`/`update.bat`）、移除 docker pull 抢注、修备用源命名空间。以下为仍开放项。

### 3.1 macOS/Linux 安装链用 `curl | bash` 执行第三方 gitee 脚本
- **严重度**：Medium
- **文件**：`scripts/start.sh`
- **影响**：Homebrew 安装首选的是第三方个人 gitee 仓库 `ineo6/homebrew-install`（非官方源），以当前用户权限直接执行；该 gitee 账号/仓库被攻陷即等于在用户机器上 RCE。`get.docker.com | sh` 同样是下载即执行、无校验。
- **建议修法**：优先用 Homebrew 官方脚本并固定到带哈希校验的版本；第三方镜像降为可选并在执行前提示来源/风险；docker 安装脚本下载后校验哈希再执行。

### 3.2 mkcert 二进制下载无校验即安装并写入系统根 CA
- **严重度**：Medium
- **文件**：`scripts/_https.sh`
- **影响**：下载的可执行文件无 sha256/签名校验即 `chmod +x` 放入 `/usr/local/bin`，随后 `mkcert -install` 把新根 CA 写入系统信任库；下载到固定 `/tmp/mkcert`（多用户机可被预置符号链接）。
- **建议修法**：固定 mkcert 版本并校验发布方 sha256/签名后再装；下载到 `mktemp` 随机文件；向用户说明会安装本地根 CA 的安全含义。

### 3.3 无降级保护：版本仅字符串相等判断，`min_version` 写了不校验
- **严重度**：Medium
- **文件**：`scripts/_update.sh`、`scripts/update.bat`、`.github/workflows/release.yml`
- **影响**：服务端（或被抢注的备用源）把 `latest` 改成一个更旧的版本号，客户端就会安装旧版 = 降级攻击，可退回含已知漏洞的版本。`min_version` 是死字段。
- **建议修法**：实现语义化版本比较，仅 `LATEST > CURRENT` 才更新；客户端强制 `min_version`；版本号纳入签名内容防回滚。

### 3.4 离线更新包 `create-update.sh` 不签名；`install-update.bat` 未接验签
- **严重度**：Medium
- **文件**：`scripts/create-update.sh`、`scripts/install-update.bat`
- **影响**：v1.4.0 给 `_update.sh`/`update.bat`/`install-update.sh` 接了验签，但"生成更新包"链路（create-update.sh）仍不签名，Windows 的 `install-update.bat` 手动安装路径也尚未接验签门。
- **建议修法**：create-update.sh 打包后调用 `sign-release.sh sign`；install-update.bat 比照 install-update.sh 加来源校验/验签。

### 3.5 `release.yml`：不签名、`version.json` 无哈希、权限非最小化
- **严重度**：Medium
- **文件**：`.github/workflows/release.yml`
- **影响**：官方发布产物没有签名或哈希，客户端无从验起；`version.json` 只给 size 不给 sha256；`contents: write` 给了仅做 lint/build 的 job。
- **建议修法**：build 后加签名步骤（Sigstore 或 Ed25519 私钥放 Actions secret），`.sig` + sha256 一并上传并写入 `version.json`；权限收敛为 job 级，仅 release/deploy 授 `contents: write`。配合 v1.4.0 的 `sign-release.sh keygen` 仪式。

### 3.6 Dockerfile 其余 UI RUN 步骤仍 `2>/dev/null || true` 静默吞错
- **严重度**：Low-Medium（v1.4.0 已让 gateway-patch.py 硬失败 + 加构建期自检）
- **文件**：`Dockerfile.custom`
- **影响**：除已修的补丁步骤外，仍有 chmod/chown 等步骤吞错（这些幂等准备可容错，但应保留 stderr 以便看到上游漂移告警）。
- **建议修法**：保留 chmod/chown 的容错，但去掉 `2>/dev/null` 让告警可见。

---

## 4. 数据丢失 / 备份（仍开放）

### 4.1 自动更新会覆盖用户的记忆/人设文件（MEMORY.md/USER.md/AGENTS.md/skills）
- **严重度**：Medium（违背"更新不影响数据"承诺）
- **文件**：`scripts/_update.sh`、`scripts/update.bat`、`scripts/create-patch.sh`、`scripts/create-update.sh`
- **影响**：AGENTS.md 让 AI 持续把用户记忆写进 `MEMORY.md`/`USER.md`/`IDENTITY.md`。一旦补丁包含这些 `.md`，在线更新就用出厂模板 `cp -f`/`copy /y` 覆盖用户积累数月的记忆与人设，无确认、无备份。而离线安装器（install-update.sh）却排除它们——两套路径行为相反，承诺至少对一半路径是假的。**这是把这些文件改成"模板+运行时副本"模式的根本动因**（也能彻底解决审计里"用户隐私进 git"的问题）。
- **建议修法**：① 把 `MEMORY.md`/`USER.md`/`IDENTITY.md`/`SOUL.md`/skills 改为 `*.example` 模板，首次启动复制为运行时副本并 gitignore；② 在线更新统一排除 `config/workspace/`（与离线安装器一致）；③ `create-patch.sh` 显式排除这些文件。

### 4.2 `reset.sh` 的"安全擦除"只覆盖 `.env`，其余明文凭据普通 rm
- **严重度**：Medium
- **文件**：`scripts/reset.sh`
- **影响**：自称"删除敏感文件"，但只有 `.env` 走 `secure_wipe`，含明文 key 的 `config/workspace/.provider`、`data/credentials`、`data/sessions` 全是普通 `rm`，U 盘上可被取证恢复；还漏清 `.gateway_token`/`.bound_providers`/`data/skills`。
- **建议修法**：所有明文敏感文件统一 `secure_wipe` 后再删；把 `.gateway_token`/`.bound_providers` 纳入清理；文档明确闪存上覆写也不完全可靠。

### 4.3 `backup.sh`/`backup.bat` 备份了错的东西，且把明文凭据复制到宿主机
- **严重度**：Medium
- **文件**：`scripts/backup.sh`、`scripts/backup.bat`
- **影响**：① backup.sh **漏掉真正不可再生的数据**——`工作区/`（用户全部文档/产出）和 `.env`（API key/各频道 token），备份的却几乎全是能从 GitHub 重新拉的脚本；② backup.bat 默认把**未加密的** `data/credentials`、`data/sessions` 复制到宿主机 `%USERPROFILE%\PocketClaw_Backup`，在公共电脑上备份一次，明文凭据就永久留在那台机器上，与"U 盘随身、数据不落地"的卖点完全相反。
- **建议修法**：把 `工作区/` 纳入备份；默认备份目标放 U 盘自身；对 `credentials`/`sessions` 先加密再落盘；向宿主机写敏感数据前显式警告"公共电脑勿用"。

### 4.4 `setup-channels.sh` 在"0/空输入"早退时不重新加密也不擦除，明文 `.env` 残留
- **严重度**：Medium
- **文件**：`scripts/setup-channels.sh`
- **影响**：用户解密 `.env` 后又改主意（输 0/全跳过），退出时把刚解密的明文 `.env`（含 API key 和各频道 token）留在 U 盘上，既不重新加密也不擦除。
- **建议修法**：记录是否解密过（类似 change-api 的 `NEED_REENCRYPT`），用 `trap EXIT` 在任何退出路径确保重新加密 + `secure_wipe`。

### 4.5 `secure_wipe` 在 U 盘闪存/日志型文件系统上无法真正擦除
- **严重度**：Medium（安全剧场）
- **文件**：`scripts/_common.sh`
- **影响**：核心卖点是"U 盘丢失 = 明文密钥已擦除"，但在 USB 闪存（FTL/磨损均衡重映射物理块）及 exFAT/NTFS/CoW 上，就地覆写不会抹掉原始物理块，原明文很可能仍可取证恢复，给用户错误的安全感；`bs=1` 逐字节写还极慢。
- **建议修法**：根本防线改为整盘/容器加密（明文 `.env` 一开始就别落盘，用内存/命名管道传给 docker）；若保留覆写，改合理块大小并在文档说明闪存上不可靠。

---

## 5. 注入 / 转义（仍开放）

### 5.1 entrypoint 生成 openclaw.json 时多个变量未做 JSON 转义（配置注入）
- **严重度**：Medium
- **文件**：`scripts/entrypoint.sh`
- **影响**：`MODEL_ID`/`PROVIDER`/`PROVIDER_LABEL`，以及频道特例分支（Google Chat/Matrix/WhatsApp 的 `GOOGLE_CHAT_*`/`MATRIX_*`/`WHATSAPP_ALLOW_FROM`）未走 `_json_escape`。这些值来自 U 盘上可写的 `.provider` 或 `.env`（威胁模型 #1/#5），含 `"`/`\` 会破坏 JSON 或被用于注入键——构造形如 `x","gateway":{"auth":{"mode":"none"` 的值可改写 gateway/auth、关掉 token 保护。WHATSAPP_ALLOW_FROM 还是唯一的发送方白名单，畸形输入可让其失效。
- **建议修法**：整份 openclaw.json 改用 `jq -n --arg`/`python json.dumps` 以数据方式构建，对所有插值字段统一转义；对 `MODEL_ID`/`PROVIDER` 做白名单（仅 `[A-Za-z0-9._/-]`）。加测试：把含 `"`/`\` 的值喂给每个频道，断言生成的 JSON 仍合法且无新增键。

### 5.2 `change-api.sh` / `setup-channels.sh` 用 `sed` 写用户密钥未转义 `& | \`
- **严重度**：Medium
- **文件**：`scripts/change-api.sh`、`scripts/setup-channels.sh`、`scripts/_common.sh`
- **影响**：用户粘贴的 key/token/密码被直接拼进 `sed s|...|VALUE|`，校验只拒空格。含 `&` 会被当"整段匹配"写坏（`ab&cd` → 把旧值插进去）；含 `\` 触发转义；含 `|` 直接报错，在 `set -euo pipefail` 下中途 abort，可能已写了一半频道、且停在重新加密之前留下明文 `.env`。
- **建议修法**：不用 sed 注入用户数据，改 `grep -v` 删旧行 + `printf '%s=%s\n'` 追加；或转义后用值中不出现的分隔符。校验阶段也拒绝/转义控制字符。

### 5.3 Windows `encrypt.bat`/`decrypt.bat` 延迟扩展静默破坏含 `!`/`^` 的密码
- **严重度**：Medium
- **文件**：`scripts/encrypt.bat`、`scripts/decrypt.bat`、`secrets/master.key.example`
- **影响**：`EnableDelayedExpansion` 下读取密码，含 `!`（中文用户最常用特殊符号之一）或 `^` 会被静默吃掉（`pa!ss!word`→`paword`）。同平台加解密因损坏方式一致而"恰好能用"，掩盖问题；换到 Mac 用真实密码必然解密失败 = 数据丢失，且无任何报错提示真因。同时密码有效熵被削弱。
- **建议修法**：把整个加/解密放进单条 PowerShell（`Read-Host -AsSecureString` 后在 PowerShell 进程内经 stdin 喂给 openssl，密码不回流 cmd 解析层）；短期缓解：检测密码含 `! ^ " %` 时拒绝并提示，使 bat 与 sh 可用字符集一致；encrypt.bat 验证阶段对原文做逐字节 diff（目前只验退出码）。

---

## 6. 技能 / Agent 安全边界（仍开放）

### 6.1 `image-tools` 对不可信图片无解压炸弹防护 + 路径穿越
- **严重度**：Medium
- **文件**：`config/workspace/skills/image-tools.md`、`Dockerfile.custom`
- **影响**：① 直接对用户上传图片 `Image.open` + resize，无 `img.verify()`、无 `Image.MAX_IMAGE_PIXELS`，解压炸弹（小文件巨像素）在 resize 前就把 2GB 容器 OOM 击垮（DoS）；Pillow 还用 `--break-system-packages` 浮动安装。② 输入/输出/EXIF 路径取自用户输入、无 workspace 约束，可穿越读 `../credentials/master.key`、写覆盖系统配置。
- **建议修法**：技能内规定先 `img.verify()` 再重开处理、全程 try/except、设并捕获 `MAX_IMAGE_PIXELS`、处理前用像素上限做闸门；所有路径先 `realpath` 规范化并断言位于 `workspace/`/`工作区/` 内；Dockerfile 固定 Pillow 版本。

### 6.2 AGENTS.md/TOOLS.md 对 agent 谎报权限边界
- **严重度**：Medium
- **文件**：`config/workspace/AGENTS.md`、`config/workspace/TOOLS.md`、`config/workspace/skills/file-processing.md`
- **影响**：AGENTS.md 称"不能执行任意系统命令"、TOOLS.md 称"入站仅本机"，但实际 `tools.profile:full`、`bind:lan`，且技能本身指示 agent 跑任意 Python（file-processing 明示用 `subprocess`）= 容器内任意命令执行。虚假的能力边界会让人低估本清单里的路径穿越、图片解析、提醒注入等弱点（它们都可经任意 Python 升级为代码执行）。
- **建议修法**：让文档与现实对齐（如实写明 agent 可在受限容器内执行代码/命令），并据此补齐输入校验与最小权限；或反向收紧执行通道（沙箱化、禁 subprocess、技能参数白名单）。

### 6.3 `skill-check` 按文件名白名单跳过内置技能（无哈希校验，可被同名篡改绕过）
- **严重度**：Medium（v1.4.0 已修"扫错目录"，此为另一缺陷）
- **文件**：`scripts/skill-check.sh`、`config/workspace/skills/file-processing.md`
- **影响**：扫描器只按 basename 放行内置技能，注释写"SHA-256 校验跳过"却根本没做哈希校验；而会执行代码的恰是这批内置技能。攻击者把恶意内容写进同名内置技能文件，skill-check 因文件名匹配直接放行、完全不扫。
- **建议修法**：内置技能改为按内容哈希（与发布版 SHA-256 清单比对）校验而非按文件名豁免；哈希不符即视为被篡改并阻止；对内置技能也跑危险模式扫描。

### 6.4 多个技能把用户数据写进 git 跟踪的 `config/workspace/` 而非 `工作区/`
- **严重度**：Medium
- **文件**：`config/workspace/skills/{notes,todo,reminders,ppt-generator,image-tools}.md`、`config/workspace/AGENTS.md`
- **影响**：九个内置技能至少五个把笔记/日程/待办/PPT/图片引到 `config/workspace/`（git 跟踪、无 ignore），等于把用户隐私放进"一次 commit 即公开"的位置；而用户按 AGENTS.md 去 `工作区/` 找文件又找不到。矛盾指令还让模型行为不稳定。
- **建议修法**：统一所有技能输出路径为 `../工作区/`（与 AGENTS.md:27 一致），修复后这类数据自然落入 ignore 范围。

### 6.5 含密钥的配置文件写入后未 `chmod 600`
- **严重度**：Medium
- **文件**：`scripts/setup-env.sh`、`scripts/change-api.sh`、`scripts/setup-channels.sh`
- **影响**：umask 022 下明文 `.env`（加密前窗口）与长期存在的 `config/workspace/.provider` 均为 644，多用户电脑上其他本地用户可读；经 backup 复制到 `$HOME` 更甚。
- **建议修法**：所有含密钥文件写入后立即 `chmod 600`（`.env`、`.provider`、`.gateway_token`、`secrets/.env.encrypted`），或脚本开头 `umask 077`。

---

## 7. 文档与现实不符（仍开放）

### 7.1 `SECURITY.md`/`LICENSE.md` 宣称"启动时自动检测文件篡改"，实际从不运行
- **严重度**：Medium
- **文件**：`docs/SECURITY.md`、`LICENSE.md`、`scripts/start.sh`、`.github/workflows/release.yml`
- **影响**：白皮书与 LICENSE 让用户相信"每次启动校验关键文件是否被篡改"，但基线 `.checksums.sha256` 从不随包分发、且 release 打包主动剥离点文件，这条防线对所有真实用户都是空操作 = 虚假安全感。
- **建议修法**：要么把 `.checksums.sha256` 纳入发布包（修 release.yml/build_zip.py 不再排除该文件、release 前自动 `--init` 并对基线签名），要么删除文档中"启动时自动检测篡改"的表述改为"需手动运行 verify-integrity.sh"。**注：v1.4.0 修复后，白皮书里关于 PBKDF2 600K、32 位 token、更新签名的多处声称已变为真，整份 `SECURITY.md` 值得做一次完整的准确性校订。**

### 7.2 `使用指南.txt` 菜单项与真实菜单不符 + WebChat 地址矛盾
- **严重度**：Medium
- **文件**：`使用指南.txt`、`README.md`、`PocketClaw.bat`、`PocketClaw.command`、`scripts/start.sh`
- **影响**：① 使用指南反复让用户点不存在的 `[8] 清理缓存`、把 `[3]` 标成"查看状态"（实际是打开聊天页），与真实 7 项菜单和 README 均矛盾；FAQ 把用户导向不存在的菜单。② WebChat 地址：使用指南教 `/chat#token=`，而程序与 README 实际用 `/#token=`，照抄会进无 token/错误页（FAQ Q4.5 的 "unauthorized" 正是此症状）。
- **建议修法**：菜单清单统一为真实 7 项（`[3]`=打开网页/聊天，无 `[8]`）；WebChat 地址统一为 `http://127.0.0.1:18789/#token=<Token>`，README §10.1/§11.1 同步。

---

## 8. 健壮性（仍开放）

### 8.1 缺 `.gitattributes`（v1.4.0 已加）— 后续保持
- v1.4.0 已新增 `.gitattributes` 强制 `.sh/.py/Dockerfile→LF`、`.bat/.ps1→CRLF`，修复了"Windows 克隆构建出无法启动的容器"。后续新增脚本注意遵循。

### 8.2 `start.bat` 构建标记文件重定向未给 `%TEMP%` 加引号
- **严重度**：Medium
- **文件**：`scripts/start.bat`
- **影响**：用户名含空格时 `%TEMP%` 形如 `C:\Users\John Doe\...`，未加引号的 `echo DONE > %TEMP%\oc_build_done.tmp` 被空格截断，标记永远写不出，前台进度条空转到 900 秒才报超时——即使后台 docker 早已成功。中文 Windows 上空格用户名不少见。
- **建议修法**：两处重定向目标都加引号 `> "%TEMP%\oc_build_done.tmp"`。

---

## 附：v1.4.0 已修复（无需再处理，仅供对照）

更新链路强制验签、移除 docker pull 抢注 + 修备用源、IM 频道强制白名单、网关默认绑 127.0.0.1、mobile.html 裸 URL XSS + 取消自动批准、凭据卫生（.gitignore + git rm --cached + build_zip 排除）、Windows PBKDF2 统一 600K + 解密双档回退、Windows token 32 位 CSPRNG、skill-check 改扫正确目录、AGENTS.md token 矛盾、notes 路径穿越、reminders 不可信、daemon.json 改写征求同意、VERSION/CHANGELOG 1.4.0、.gitattributes 换行归一、OpenClaw 升级到 2026.6.5（gateway-patch 重写 + 配置 schema 适配 + node 升级 + 版本钉死）。

---

## 建议处理顺序

1. **立刻**：0.1 刷新 Anthropic（及其余）模型清单（3 天内退役）。
2. **高优先（可利用安全）**：2.1 Chromium 沙箱、3.1 curl\|bash gitee、1.1/1.2/1.3 收敛 origin 通配符与弱默认 token、5.1/5.2 注入转义、6.1 image-tools。
3. **数据安全**：4.1 更新覆盖记忆文件（连带做"模板+运行时副本"重构）、4.2 reset、4.3 backup、5.3 Windows 密码字符。
4. **完整性闭环**：3.5 CI 签名 + 3.3 降级保护 + 3.4 离线包签名（配合 v1.4.0 的 keygen 仪式）、7.1 校订 SECURITY.md。
5. **文档/健壮性**：7.2 菜单与地址、8.2 `%TEMP%` 引号、6.2/6.4 技能边界与输出路径。
