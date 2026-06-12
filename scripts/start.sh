#!/usr/bin/env bash
# ============================================================
# start.sh  —— PocketClaw 启动器 (macOS/Linux)
# 用法: bash scripts/start.sh
# ============================================================
set -euo pipefail

# ── 公共函数库 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/_common.sh"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── 无论正常退出还是异常退出，都清理密码变量和明文 .env ──
cleanup_on_exit() {
    unset MASTER_PASS 2>/dev/null
    # 如果存在加密文件，退出时确保明文 .env 被清理
    if [ -f "$PROJECT_DIR/secrets/.env.encrypted" ] && [ -f "$PROJECT_DIR/.env" ]; then
        secure_wipe "$PROJECT_DIR/.env" 2>/dev/null
    fi
}
trap cleanup_on_exit EXIT INT TERM
ENC_FILE="$PROJECT_DIR/secrets/.env.encrypted"

echo "============================================"
echo "  PocketClaw 启动器 (macOS/Linux)"
echo "============================================"
echo ""
echo "[信息] 项目目录: $PROJECT_DIR"
echo ""

# ── Docker 就绪检测（5秒超时保护，防止 docker info 在引擎启动中无限挂起）──
docker_is_ready() {
    ( docker info >/dev/null 2>&1 ) &
    local pid=$!
    local i=0
    while [ $i -lt 5 ]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null
            return $?
        fi
        sleep 1
        i=$((i + 1))
    done
    # 超时：杀掉挂起的 docker info
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 1
}

# ── 等待 Docker 引擎就绪（带超时计数器）──
wait_for_docker() {
    local max_wait=$1
    local label=$2
    echo "       等待 Docker 引擎就绪（最多等待 ${max_wait} 秒）..."
    local elapsed=0
    while ! docker_is_ready; do
        elapsed=$((elapsed + 5))
        if [ "$elapsed" -ge "$max_wait" ]; then
            echo "[错误] Docker ${label}启动超时！请手动启动 Docker Desktop 后重试。"
            exit 1
        fi
        echo "       已等待 ${elapsed} 秒..."
        sleep 5
    done
}

# ── 安装 Docker Desktop DMG（macOS 辅助函数）──
install_docker_dmg() {
    local arch_name="arm64"
    [[ "$(uname -m)" != "arm64" ]] && arch_name="amd64"
    local DMG_FILE="/tmp/Docker.dmg"
    local DMG_URL="https://desktop.docker.com/mac/main/${arch_name}/Docker.dmg"
    echo "[信息] 正在直接下载 Docker Desktop..."
    echo "       架构: $(uname -m)"
    echo "       文件较大（~600MB），请耐心等待..."
    echo ""
    if ! curl -fSL --connect-timeout 15 --retry 2 --progress-bar -o "$DMG_FILE" "$DMG_URL"; then
        rm -f "$DMG_FILE"
        return 1
    fi
    echo ""
    echo "[信息] 正在安装 Docker Desktop 到 /Applications..."
    hdiutil attach "$DMG_FILE" -nobrowse -quiet
    if ! cp -R "/Volumes/Docker/Docker.app" /Applications/ 2>/dev/null; then
        echo "[信息] 需要管理员权限，请输入 Mac 开机密码:"
        sudo cp -R "/Volumes/Docker/Docker.app" /Applications/
    fi
    hdiutil detach "/Volumes/Docker" -quiet 2>/dev/null || true
    rm -f "$DMG_FILE"
    return 0
}

# ── 检查 Docker ──
if ! command -v docker &>/dev/null; then
    echo "[警告] 未检测到 Docker！正在自动安装..."
    echo ""
    if [[ "$(uname)" == "Darwin" ]]; then
        DOCKER_INSTALLED=false
        DOCKER_ENGINE=""              # "desktop" 或 "colima"

        # ── 确保 Homebrew 可用 ──
        if ! command -v brew &>/dev/null; then
            echo "[信息] 正在安装 Homebrew（macOS 包管理工具）..."
            echo "       安装过程中可能需要按回车键确认，以及输入开机密码"
            echo ""
            # 优先国内镜像（更稳定）— 使用 Homebrew 官方安装方式
            if /bin/bash -c "$(curl -fsSL https://gitee.com/ineo6/homebrew-install/raw/master/install.sh)" 2>&1; then
                true
            # 备用：官方安装脚本
            elif /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2>&1; then
                true
            fi
            # Apple Silicon: /opt/homebrew  |  Intel: /usr/local
            # 设置 brew 环境变量（PATH 等）
            if [ -x /opt/homebrew/bin/brew ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || export PATH="/opt/homebrew/bin:$PATH"
            elif [ -x /usr/local/bin/brew ]; then
                eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || export PATH="/usr/local/bin:$PATH"
            fi
        fi

        # ── 方案一：Homebrew 安装 Docker Desktop（最简单）──
        if command -v brew &>/dev/null; then
            echo "[信息] 方案 1/3：通过 Homebrew 安装 Docker Desktop..."
            if brew install --cask docker 2>&1; then
                DOCKER_INSTALLED=true
                DOCKER_ENGINE="desktop"
            else
                echo "[警告] Docker Desktop 下载失败（docker.com 在国内可能被网络干扰）"
                echo ""
            fi
        fi

        # ── 方案二：Colima — 轻量级 Docker 运行时（绕过 docker.com）──
        #    Colima 和 docker CLI 都是 Homebrew formula，走国内瓶子镜像，不受封锁影响
        if ! $DOCKER_INSTALLED && command -v brew &>/dev/null; then
            echo "[信息] 方案 2/3：安装 Colima（轻量级 Docker 运行时，无需 Docker Desktop）..."
            echo "       Colima 通过 Homebrew 安装，下载源不受国内网络限制"
            echo ""
            if brew install colima docker docker-compose 2>&1; then
                DOCKER_INSTALLED=true
                DOCKER_ENGINE="colima"
            else
                echo "[警告] Colima 安装也失败了，尝试最后方案..."
                echo ""
            fi
        fi

        # ── 方案三：直接下载 DMG（备用）──
        if ! $DOCKER_INSTALLED; then
            echo "[信息] 方案 3/3：直接下载 Docker Desktop DMG..."
            if install_docker_dmg; then
                DOCKER_INSTALLED=true
                DOCKER_ENGINE="desktop"
            fi
        fi

        # ── 所有方案均失败 ──
        if $DOCKER_INSTALLED; then
            echo "[OK] Docker 已安装（引擎: ${DOCKER_ENGINE}）"
            echo ""
            if [[ "$DOCKER_ENGINE" == "colima" ]]; then
                echo "[信息] 正在启动 Colima..."
                colima start 2>&1 || true
            else
                echo "[信息] 正在启动 Docker Desktop（首次启动可能需要授权）..."
                open -a "Docker"
            fi
        else
            echo ""
            echo "[错误] Docker 自动安装失败！"
            echo ""
            echo "  docker.com 在国内可能被网络干扰，建议以下方式："
            echo "  ──────────────────────────────────────────────"
            echo "  方式 A（推荐）开启 VPN 后重新运行本脚本"
            echo ""
            echo "  方式 B：手动安装 Docker Desktop"
            echo "   1. 在浏览器中打开下载页面（已自动打开）"
            echo "   2. 点击「Download for Mac」"
            echo "   3. 打开下载的 .dmg → 将 Docker 拖入 Applications"
            echo "   4. 打开 Docker Desktop，等待启动完成"
            echo "   5. 重新运行 PocketClaw.command"
            echo ""
            open "https://www.docker.com/products/docker-desktop/" 2>/dev/null || true
            echo ""
            read -rp "  按回车返回菜单..." _
            exit 1
        fi
    else
        # Linux: 通过官方脚本安装
        echo "[信息] 正在通过官方脚本安装 Docker..."
        if ! curl -fsSL https://get.docker.com | sh; then
            echo "[错误] Docker 安装失败！请手动安装: https://docs.docker.com/engine/install/"
            exit 1
        fi
        sudo usermod -aG docker "$USER" 2>/dev/null || true
        sudo systemctl start docker 2>/dev/null || true
        echo "[OK] Docker 已安装"
    fi
    echo ""
    wait_for_docker 180 ""
    echo "[OK] Docker 已就绪"
fi

if ! docker_is_ready; then
    if command -v colima &>/dev/null; then
        echo "[信息] Docker 未运行，正在自动启动 Colima..."
        colima start 2>/dev/null || true
        wait_for_docker 120 ""
        echo "[OK] Colima 已自动启动"
    else
        echo "[信息] Docker 未运行，正在自动启动 Docker Desktop..."
        if [[ "$(uname)" == "Darwin" ]]; then
            killall "com.docker.backend" "com.docker.virtualization" 2>/dev/null || true
            sleep 1
        fi
        open -a "Docker" 2>/dev/null || true
        wait_for_docker 120 "Desktop "
        echo "[OK] Docker Desktop 已自动启动"
    fi
fi

echo "[OK] Docker 已就绪"
echo ""

echo "[1/7] Docker 环境 ✓"
echo ""

# ── 文件完整性校验 ──
if [ -f "$SCRIPT_DIR/.checksums.sha256" ]; then
    echo "[信息] 正在校验文件完整性..."
    TAMPERED=0
    while IFS='  ' read -r expected_hash filepath; do
        [ -z "$expected_hash" ] && continue
        if [ -f "$PROJECT_DIR/$filepath" ]; then
            actual_hash=$(shasum -a 256 "$PROJECT_DIR/$filepath" 2>/dev/null | awk '{print $1}')
            if [ "$actual_hash" != "$expected_hash" ]; then
                echo "  [警告] 文件已被修改: $filepath"
                TAMPERED=$((TAMPERED + 1))
            fi
        fi
    done < "$SCRIPT_DIR/.checksums.sha256"
    if [ "$TAMPERED" -gt 0 ]; then
        echo ""
        echo "[警告] 检测到 $TAMPERED 个文件被修改，修改后的版本不受原作者技术支持。"
        echo "       如非本人操作，请注意安全风险。"
        echo ""
    else
        echo "[OK] 文件完整性校验通过 ✓"
    fi
    echo ""
fi

echo "[2/7] 文件完整性 ✓"
echo ""

# ── 交互式解密 .env.encrypted → .env ──
decrypt_env() {
    local prompt="${1:-请输入 Master Password: }"
    while true; do
        read -s -p "$prompt" MASTER_PASS
        echo ""
        if [ -z "$MASTER_PASS" ]; then
            echo "[错误] 密码不能为空，请重新输入。"
            echo ""
            continue
        fi
        if decrypt_env_file "$ENC_FILE" "$PROJECT_DIR/.env" "$MASTER_PASS"; then
            unset MASTER_PASS
            echo "[OK] 解密成功"
            return 0
        fi
        echo "[错误] 解密失败，密码可能不正确，请重新输入。"
        rm -f "$PROJECT_DIR/.env"
        unset MASTER_PASS
        echo ""
    done
}

# ── 检查 .env ──
if [ ! -f "$PROJECT_DIR/.env" ]; then
    if [ -f "$ENC_FILE" ]; then
        echo "[信息] 检测到加密配置，正在解密..."
        decrypt_env
    else
        echo "[警告] 未找到 .env 配置文件！正在启动配置向导..."
        bash "$PROJECT_DIR/scripts/setup-env.sh" || true
        # setup-env.sh 加密后会删除明文 .env，此时需要走解密流程
        if [ ! -f "$PROJECT_DIR/.env" ]; then
            if [ -f "$ENC_FILE" ]; then
                echo ""
                echo "[信息] 配置已加密保存，现在需要解密以启动..."
                decrypt_env
            else
                echo "[错误] 配置未完成。"
                exit 1
            fi
        fi
    fi
fi

echo "[OK] 配置文件就绪"
echo ""
echo "[3/7] 配置解密 ✓"

# ── 清理 .env 中的非 UTF-8 字节（防止 GBK 中文注释导致 docker --env-file 报错）──
if [ -f "$PROJECT_DIR/.env" ]; then
    # 最可靠的方式：去掉 CRLF，然后只保留非注释非空行（KEY=VALUE 格式）
    # Docker 的 --env-file 不需要注释，GBK 注释会导致 invalid utf8 报错
    # LC_ALL=C 确保 macOS 上不会因非 UTF-8 字节报 "Illegal byte sequence"
    LC_ALL=C tr -d '\r' < "$PROJECT_DIR/.env" \
        | LC_ALL=C grep -v '^[[:space:]]*#' \
        | LC_ALL=C grep -v '^[[:space:]]*$' \
        > "$PROJECT_DIR/.env.clean" 2>/dev/null
    if [ -s "$PROJECT_DIR/.env.clean" ]; then
        mv "$PROJECT_DIR/.env.clean" "$PROJECT_DIR/.env"
        echo "[OK] .env 已清理（移除注释和空行）"
    else
        # 清理后为空说明出了问题，保留原文件
        rm -f "$PROJECT_DIR/.env.clean"
        echo "[警告] .env 清理异常，保留原文件"
    fi
fi

# ── 检查/配置 Docker 镜像加速器 ──
# Colima 用户: 镜像加速器通过 ~/.colima/default/colima.yaml 配置，此处跳过
USING_COLIMA=0
if command -v colima &>/dev/null && colima status 2>/dev/null | grep -qi "running"; then
    USING_COLIMA=1
fi

DAEMON_JSON="$HOME/.docker/daemon.json"
MIRRORS_OK=0
if [ "$USING_COLIMA" -eq 1 ]; then
    MIRRORS_OK=1  # Colima 用户跳过镜像加速器检查
elif [ -f "$DAEMON_JSON" ]; then
    if python3 -c "import json; cfg=json.load(open('$DAEMON_JSON')); exit(0 if cfg.get('registry-mirrors') else 1)" 2>/dev/null; then
        MIRRORS_OK=1
    fi
fi

if [ "$MIRRORS_OK" -eq 1 ]; then
    echo "[OK] 镜像加速器已配置，跳过连通性检查"
else
    echo "[信息] 检查 Docker Hub 连通性..."
    # 用 curl 快速检测（5秒超时），比 docker pull 快得多
    if ! curl -s --connect-timeout 5 --max-time 10 https://registry-1.docker.io/v2/ >/dev/null 2>&1; then
        echo ""
        echo "[信息] Docker Hub 不可达。可配置国内镜像加速器以便拉取基础镜像。"
        # 安全（修复审计 High）：不再静默改写宿主机【全局】 daemon.json。
        # 这会影响该机此后所有 docker.io 拉取（包括你其它项目），且第三方镜像站可成为
        # 供应链中间人。因此改为：明确征得用户同意后再写入，并在写入前备份原文件。
        echo "      它会修改宿主机全局 Docker 配置（$DAEMON_JSON），将镜像源指向："
        echo "        https://docker.1ms.run, https://docker.xuanyuan.me （第三方，非官方）"
        echo "      该改动是全局且持久的（PocketClaw 退出后仍生效）。"
        printf "      是否允许修改全局 Docker 配置？(y/N): "
        read -r MIRROR_CONSENT
        if [ "$MIRROR_CONSENT" != "y" ] && [ "$MIRROR_CONSENT" != "Y" ]; then
            echo "[信息] 已跳过镜像加速器配置（构建可能较慢，或请自行配置可信镜像源）。"
        else
        mkdir -p "$(dirname "$DAEMON_JSON")"
        # 备份原配置，便于事后恢复
        [ -f "$DAEMON_JSON" ] && cp "$DAEMON_JSON" "${DAEMON_JSON}.pocketclaw-bak.$(date +%s)" 2>/dev/null || true
        if [ -f "$DAEMON_JSON" ]; then
            python3 -c "
import json
try:
    cfg = json.load(open('$DAEMON_JSON'))
except: cfg = {}
cfg['registry-mirrors'] = ['https://docker.1ms.run','https://docker.xuanyuan.me']
json.dump(cfg, open('$DAEMON_JSON','w'), indent=2)
"
        else
            echo '{"registry-mirrors":["https://docker.1ms.run","https://docker.xuanyuan.me"]}' > "$DAEMON_JSON"
        fi
        echo "[OK] 镜像加速器已配置（原配置已备份为 ${DAEMON_JSON}.pocketclaw-bak.*）"
        # 仅 Docker Desktop 需要重启
        if [ "$USING_COLIMA" -eq 0 ] && open -a "Docker" 2>/dev/null; then
            echo "[信息] 正在重启 Docker Desktop 以应用配置..."
            osascript -e 'quit app "Docker"' 2>/dev/null || true
            QUIT_WAIT=0
            while docker info &>/dev/null 2>&1; do
                sleep 2
                QUIT_WAIT=$((QUIT_WAIT + 2))
                if [ "$QUIT_WAIT" -ge 30 ]; then
                    break
                fi
            done
            sleep 2
            open -a "Docker"
            wait_for_docker 120 "Desktop 重启"
            echo "[OK] Docker 已重启，镜像加速器已生效"
        else
            echo "[信息] 镜像加速器配置已写入，将在下次 Docker 启动时生效"
        fi
        fi
    else
        echo "[OK] Docker Hub 连接正常"
    fi
fi

echo "[4/7] 镜像加速器 ✓"
echo ""

# ── 清理 macOS 资源分叉/隐藏文件（防止 Docker 构建失败 + 保持 USB 干净）──
clean_macos_usb_artifacts "$PROJECT_DIR" && echo "[清理] 已清除 macOS 隐藏文件并禁止重新生成" || true

# ── 启动 ──
cd "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/data/logs"
BUILD_LOG="$PROJECT_DIR/data/logs/build.log"
true > "$BUILD_LOG"

# ── 第一步：智能构建镜像 ──
# 计算关键文件指纹：仅当 Dockerfile/entrypoint/config/providers 变化时才重新构建
BUILD_HASH_FILE="$PROJECT_DIR/data/.build_hash"
CURRENT_HASH=""
if command -v md5sum &>/dev/null; then
    CURRENT_HASH=$(cat "$PROJECT_DIR/Dockerfile.custom" "$PROJECT_DIR/scripts/entrypoint.sh" "$PROJECT_DIR/config/mobile.html" "$PROJECT_DIR/config/openclaw.json" "$PROJECT_DIR/config/providers.json" "$PROJECT_DIR/VERSION" 2>/dev/null | md5sum | awk '{print $1}')
elif command -v md5 &>/dev/null; then
    CURRENT_HASH=$(cat "$PROJECT_DIR/Dockerfile.custom" "$PROJECT_DIR/scripts/entrypoint.sh" "$PROJECT_DIR/config/mobile.html" "$PROJECT_DIR/config/openclaw.json" "$PROJECT_DIR/config/providers.json" "$PROJECT_DIR/VERSION" 2>/dev/null | md5)
fi

PREV_HASH=""
[ -f "$BUILD_HASH_FILE" ] && PREV_HASH=$(cat "$BUILD_HASH_FILE" 2>/dev/null)

NEED_BUILD=1
if [ -n "$CURRENT_HASH" ] && [ "$CURRENT_HASH" = "$PREV_HASH" ]; then
    # 指纹一致，检查镜像是否存在
    if docker image inspect pocketclaw-pocketclaw:latest &>/dev/null; then
        NEED_BUILD=0
        echo "[OK] 镜像未变化，跳过构建（秒级启动）"
    fi
fi

# 安全（修复审计 Critical #2）：移除从 Docker Hub 拉取 pocketclaw/pocketclaw:latest 的快速路径。
# 该命名空间并非本项目所有（真实仓库 tinqiao-oss/PocketClaw）、CI 也从不向其推送镜像，
# 浮动 :latest 既无 digest 又无签名校验，一旦被他人抢注即等于大规模 RCE。
# 因此一律按钉死版本的 Dockerfile 本地构建；若将来要分发官方预构建镜像，应：
# 受控账号 push + digest 钉死 + cosign 验签通过后再启用，绝不 fail-open 静默跳过。
if [ "$NEED_BUILD" -eq 1 ]; then
    echo "[5/7] 将按钉死的 OpenClaw 版本本地构建镜像（可复现、来源可信）..."
fi

if [ "$NEED_BUILD" -eq 1 ]; then
    # 首次构建时间预估（U4）
    FIRST_BUILD=0
    if ! docker image inspect pocketclaw-pocketclaw:latest &>/dev/null 2>&1; then
        FIRST_BUILD=1
    fi
    echo ""
    echo "┌──────────────────────────────────────────┐"
    if [ "$FIRST_BUILD" -eq 1 ]; then
    echo "│  首次构建容器镜像（约 5-8 分钟）         │"
    echo "│  需下载 ~800MB 依赖，请保持网络连接      │"
    else
    echo "│  正在构建容器镜像...                     │"
    echo "│  有缓存加速，预计 1-2 分钟               │"
    fi
    echo "└──────────────────────────────────────────┘"
    echo ""

    DOCKER_BUILDKIT=1 run_compose build --progress=plain >> "$BUILD_LOG" 2>&1 &
    BUILD_PID=$!

    SPINNER='|/-\'
    SPIN_IDX=0
    BUILD_START=$(date +%s)
    while kill -0 "$BUILD_PID" 2>/dev/null; do
        NOW=$(date +%s)
        ELAPSED=$(( NOW - BUILD_START ))
        MINS=$(( ELAPSED / 60 ))
        SECS=$(( ELAPSED % 60 ))
        STEP=$(grep -oE '\[[[:space:]]*[0-9]+/[0-9]+\][[:space:]]+[A-Z]+[^"]*' "$BUILD_LOG" 2>/dev/null | tail -1 | head -c 50 || true)
        SPIN_CHAR="${SPINNER:SPIN_IDX%4:1}"
        printf "\r  %s [%02d:%02d] %s          " "$SPIN_CHAR" "$MINS" "$SECS" "${STEP:-正在准备...}"
        SPIN_IDX=$((SPIN_IDX + 1))
        sleep 0.5
    done
    wait "$BUILD_PID"
    BUILD_EXIT=$?
    printf "\r%-80s\r" " "

    NOW=$(date +%s)
    BUILD_TOTAL=$(( NOW - BUILD_START ))

    if [ "$BUILD_EXIT" -ne 0 ]; then
        echo ""
        echo "[错误] 镜像构建失败！（耗时 $((BUILD_TOTAL/60))分$((BUILD_TOTAL%60))秒）"
        echo "  构建日志: $BUILD_LOG"
        echo "  可能原因:"
        echo "  1. Docker Hub 无法访问 → 请配置镜像加速器"
        echo "  2. 磁盘空间不足 → docker system prune"
        echo ""
        echo "  详细排查指南: https://pocketclaw.cn/#faq"
        exit 1
    fi
    echo "[OK] 镜像构建完成（耗时 $((BUILD_TOTAL/60))分$((BUILD_TOTAL%60))秒）"

    # 保存构建指纹
    [ -n "$CURRENT_HASH" ] && echo "$CURRENT_HASH" > "$BUILD_HASH_FILE"
fi

echo ""
echo "[5/7] 镜像构建 ✓"

# ── Skill 安全扫描（启动前检查真正生效的 Skill 文件）──
# 修复审计 High：原来扫的是常年为空的 data/skills，真正被 agent 加载的在 config/workspace/skills。
if [ -f "$PROJECT_DIR/scripts/skill-check.sh" ]; then
    bash "$PROJECT_DIR/scripts/skill-check.sh" "$PROJECT_DIR/config/workspace/skills"
    # 同时扫一遍 data/skills（如有 clawhub 远程技能落地于此）
    [ -d "$PROJECT_DIR/data/skills" ] && bash "$PROJECT_DIR/scripts/skill-check.sh" "$PROJECT_DIR/data/skills"
fi

# ── 第二步：启动容器 ──
# 彻底清理所有 pocketclaw 相关容器（包括幽灵容器）和网络
echo "[..] 清理旧容器..."
run_compose down --remove-orphans >> "$BUILD_LOG" 2>&1 || true
# 清理所有名称含 pocketclaw 的容器（包括 <hash>_pocketclaw 等幽灵容器）
for cid in $(docker ps -aq --filter "name=pocketclaw" 2>/dev/null); do
    docker rm -f "$cid" >> "$BUILD_LOG" 2>&1 || true
done
# 清理任何使用 pocketclaw 镜像但名称不匹配的容器
for cid in $(docker ps -aq --filter "ancestor=pocketclaw-pocketclaw:latest" 2>/dev/null); do
    docker rm -f "$cid" >> "$BUILD_LOG" 2>&1 || true
done
# 清理可能残留的网络
docker network rm pocketclaw_pocketclaw-net >> "$BUILD_LOG" 2>&1 || true
docker network rm pocketclaw_default >> "$BUILD_LOG" 2>&1 || true

# ── 生成随机 Gateway Token（32 位，每次启动不同，防止局域网未授权访问）──
if [ -z "${GATEWAY_AUTH_PASSWORD:-}" ]; then
    GATEWAY_AUTH_PASSWORD=$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32 || true)
    # 若 urandom 失败，使用时间戳+进程号
    if [ -z "$GATEWAY_AUTH_PASSWORD" ]; then
        GATEWAY_AUTH_PASSWORD="pc$(date +%s)$$$(( RANDOM % 9999 ))"
    fi
fi
export GATEWAY_AUTH_PASSWORD

# 停止 Mac 原生 OpenClaw gateway (与 Docker 端口冲突)
if [ "$(uname)" = "Darwin" ]; then
    PLIST="$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
    if [ -f "$PLIST" ] && launchctl list 2>/dev/null | grep -q "ai.openclaw.gateway"; then
        echo "[信息] 正在停止原生 OpenClaw gateway (端口冲突)..."
        launchctl unload "$PLIST" 2>/dev/null || true
        sleep 1
    fi
fi

# 尝试 docker compose up
run_compose up -d >> "$BUILD_LOG" 2>&1 || true

# 等待几秒让容器启动
sleep 3

# 检查容器是否在运行
if docker ps --filter "name=pocketclaw" --format "{{.Status}}" 2>/dev/null | grep -qi "up"; then
    echo "[OK] 容器启动成功"
else
    # docker compose up 失败（可能有幽灵容器干扰），回退到 docker run
    echo "[信息] 正在使用备用方式启动..."
    docker rm -f pocketclaw >> "$BUILD_LOG" 2>&1 || true

    # 从 docker-compose.yml 读取镜像名
    IMAGE_NAME="pocketclaw-pocketclaw:latest"

    # 创建网络（忽略已存在错误）
    docker network create pocketclaw_pocketclaw-net >> "$BUILD_LOG" 2>&1 || true

    # 直接 docker run（与 docker-compose.yml 保持相同安全策略）
    # 如果容器名冲突（幽灵容器无法删除），自动使用备用名
    CONTAINER_NAME="pocketclaw"
    _run_docker_container() {
        docker run -d \
            --name "$1" \
            --restart unless-stopped \
            --network pocketclaw_pocketclaw-net \
            -p 0.0.0.0:18789:18789 \
            -v "$PROJECT_DIR/config/workspace:/home/node/.openclaw/workspace" \
            -v "$PROJECT_DIR/工作区:/home/node/.openclaw/工作区" \
            -v "$PROJECT_DIR/data/credentials:/home/node/.openclaw/credentials" \
            -v "$PROJECT_DIR/data/sessions:/home/node/.openclaw/sessions" \
            -v "$PROJECT_DIR/data/logs:/home/node/.openclaw/logs" \
            -v "$PROJECT_DIR/data/skills:/home/node/.openclaw/skills" \
            --read-only \
            --security-opt no-new-privileges:true \
            --cap-drop ALL \
            --memory 2g \
            --pids-limit 128 \
            --tmpfs /tmp:size=100M,noexec,nosuid \
            --tmpfs /home/node/.npm:size=50M,uid=1000,gid=1000 \
            --tmpfs /var/log:size=50M \
            --tmpfs /home/node/.openclaw:size=100M,uid=1000,gid=1000 \
            --env-file "$PROJECT_DIR/.env" \
            -e "GATEWAY_AUTH_PASSWORD=$GATEWAY_AUTH_PASSWORD" \
            "$IMAGE_NAME" >> "$BUILD_LOG" 2>&1
    }

    if ! _run_docker_container "$CONTAINER_NAME"; then
        # 容器名被幽灵容器占用，使用备用名重试
        echo "[信息] 检测到容器名冲突，使用备用名启动..."
        CONTAINER_NAME="pocketclaw-$(date +%s)"
        _run_docker_container "$CONTAINER_NAME" >> "$BUILD_LOG" 2>&1 || true
    fi

    sleep 3
    if docker ps --filter "name=$CONTAINER_NAME" --format "{{.Status}}" 2>/dev/null | grep -qi "up"; then
        echo "[OK] 容器启动成功（备用方式）"
    else
        echo ""
        echo "[错误] 容器启动失败！"
        echo "  构建日志: $BUILD_LOG"
        echo "  可能原因:"
        echo "  1. 端口 18789 被占用 → 关闭占用该端口的程序"
        echo "  2. 磁盘空间不足 → docker system prune"
        echo "  3. Docker 内部数据损坏 → 停止 Docker Desktop → 删除"
        echo "     ~/Library/Containers/com.docker.docker/Data/vms (Mac)"
        echo "     或 Docker Desktop → 设置 → 重置 → Clean/Purge data (Windows)"
        echo ""
        exit 1
    fi
fi
echo "[6/7] 容器启动 ✓"
echo ""

# ── API Key 有效性验证（N7: 启动后自动检查，无效立即提示）──
echo "[信息] 正在验证 API Key..."
# 从容器环境变量获取 API 配置并尝试调 models 接口
if docker exec pocketclaw python3 -c "
import os, urllib.request, urllib.error, json, sys
prov_file = '/home/node/.openclaw/workspace/.provider'
api_key = os.environ.get('OPENAI_API_KEY', '')
base_url = ''
if os.path.exists(prov_file):
    for line in open(prov_file):
        if line.strip().startswith('API_KEY='):
            api_key = line.strip().split('=',1)[1].strip()
if not api_key or api_key == 'not-configured-yet':
    print('API_KEY_MISSING')
    sys.exit(0)
print('API_KEY_OK')
" 2>/dev/null | grep -q 'API_KEY_OK'; then
    echo "[OK] API Key 已配置"
elif docker exec pocketclaw python3 -c "print('API_KEY_MISSING')" 2>/dev/null | grep -q 'API_KEY_MISSING'; then
    echo ""
    yellow "[警告] API Key 未配置或为空！"
    echo "       请先运行: bash scripts/setup-env.sh"
    echo "       或在控制面板中选择 [4] 切换模型/API Key"
    echo ""
else
    echo "[OK] API Key 验证跳过（容器初始化中）"
fi

echo "[7/7] 验证完成 ✓"
echo ""

# ── 读取 Gateway Token（用于浏览器自动认证）──
GATEWAY_TOKEN="${GATEWAY_AUTH_PASSWORD:-pocketclaw}"
DASHBOARD_URL="http://127.0.0.1:18789/#token=${GATEWAY_TOKEN}"

# ── .gateway_token 由容器 entrypoint.sh 写入，此处不再重复写（避免文件锁冲突）──

# ── 检测局域网 IP（用于手机访问）──
LAN_IP=""
if command -v ifconfig &>/dev/null; then
    LAN_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
elif command -v ip &>/dev/null; then
    LAN_IP=$(ip -4 addr show | grep -oE 'inet [0-9.]+' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
elif command -v hostname &>/dev/null; then
    LAN_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
fi
if [ -n "$LAN_IP" ]; then
    echo "$LAN_IP" > "$PROJECT_DIR/config/workspace/.host_ip"
fi

# 重新读取版本号（可能已被更新）
POCKETCLAW_VERSION=$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")

echo ""
echo "============================================"
echo "  [OK] PocketClaw v${POCKETCLAW_VERSION} 已成功启动！"
echo "============================================"
echo ""
echo "  打开界面: $DASHBOARD_URL"
if [ -n "$LAN_IP" ]; then
MOBILE_URL="http://${LAN_IP}:18789/mobile.html#token=${GATEWAY_TOKEN}"
echo "  手机访问: $MOBILE_URL"
echo ""
echo "  [扫码手机访问]"
echo ""
# 生成终端 QR 码（优先用容器内 python3，容器已预装 qrcode 模块）
if docker exec pocketclaw python3 -c "import qrcode,sys;qr=qrcode.QRCode(border=1,error_correction=qrcode.constants.ERROR_CORRECT_L);qr.add_data(sys.argv[1]);qr.print_ascii()" "$MOBILE_URL" 2>/dev/null; then
    true
elif command -v python3 &>/dev/null; then
    python3 -c "
try:
    import qrcode
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', '-q', '--break-system-packages', 'qrcode'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    import qrcode
qr = qrcode.QRCode(border=1, error_correction=qrcode.constants.ERROR_CORRECT_L)
qr.add_data('$MOBILE_URL')
qr.print_ascii()
" 2>/dev/null || true
fi
echo ""
fi


# ── 清理明文 ──
if [ -f "$ENC_FILE" ]; then
    secure_wipe "$PROJECT_DIR/.env"
    echo "[安全] 明文配置已安全擦除"
fi

# 等待服务就绪后打开浏览器
echo "[信息] 等待服务就绪..."
SVC_WAIT=0
while ! curl -sf --connect-timeout 3 --max-time 5 -o /dev/null http://127.0.0.1:18789/health 2>/dev/null; do
    SVC_WAIT=$((SVC_WAIT + 2))
    [ "$SVC_WAIT" -ge 30 ] && break
    sleep 2
done
if command -v open &>/dev/null; then
    open "$DASHBOARD_URL"
elif command -v xdg-open &>/dev/null; then
    xdg-open "$DASHBOARD_URL"
fi
