#!/usr/bin/env bash
# ============================================================
# install-update.sh  —— PocketClaw 一键更新安装器 (macOS/Linux)
#
# 朋友收到更新包后，解压并运行: bash install-update.sh
# 自动搜索 U 盘 → 创建回滚备份 → 安装更新 → 可选重启
#
# 不会覆盖: secrets/ data/ .env openclaw-src/ config/workspace/
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/_payload"

# _common.sh 可能在同级目录或 _payload/scripts/ 内
if [ -f "$SCRIPT_DIR/_common.sh" ]; then
    source "$SCRIPT_DIR/_common.sh"
elif [ -f "$PAYLOAD_DIR/scripts/_common.sh" ]; then
    source "$PAYLOAD_DIR/scripts/_common.sh"
else
    # 定义最小依赖函数，确保脚本仍可运行
    run_compose() { docker compose "$@" 2>/dev/null || docker-compose "$@"; }
    secure_wipe() { dd if=/dev/urandom of="$1" bs="$(stat -f%z "$1" 2>/dev/null || stat -c%s "$1")" count=1 conv=notrunc 2>/dev/null; rm -f "$1"; }
fi

# ── 颜色 ──
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }
cyan()  { printf "\033[36m%s\033[0m\n" "$*"; }

echo ""
cyan "╔══════════════════════════════════════╗"
cyan "║   PocketClaw 更新安装器            ║"
cyan "╚══════════════════════════════════════╝"
echo ""

# ── 显示更新信息 ──
if [ -f "$SCRIPT_DIR/UPDATE_INFO.txt" ]; then
    cat "$SCRIPT_DIR/UPDATE_INFO.txt"
    echo "============================================"
    echo ""
fi

# ── 检查 payload ──
if [ ! -d "$PAYLOAD_DIR" ]; then
    red "[错误] 未找到更新文件 (_payload 目录)"
    echo "请确保解压了完整的更新包后运行此脚本。"
    exit 1
fi

# ── 自动搜索 PocketClaw ──
TARGET_DIR=""

# 方法1: 检查父目录（更新包在 U 盘内解压的情况）
if [ -f "$SCRIPT_DIR/../docker-compose.yml" ] && [ -d "$SCRIPT_DIR/../scripts" ]; then
    TARGET_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# 方法2: 扫描挂载点
if [ -z "$TARGET_DIR" ]; then
    yellow "[信息] 正在搜索 PocketClaw 安装位置..."
    for search_dir in /Volumes/*/PocketClaw /media/*/PocketClaw /run/media/*/PocketClaw; do
        if [ -f "$search_dir/docker-compose.yml" ] 2>/dev/null; then
            TARGET_DIR="$search_dir"
            echo "  找到: $TARGET_DIR"
            break
        fi
    done
fi

# 方法3: 手动输入
if [ -z "$TARGET_DIR" ]; then
    echo ""
    yellow "[警告] 未自动找到 PocketClaw 目录。"
    echo "       请确保 U 盘已插入。"
    echo ""
    read -rp "请输入 PocketClaw 的完整路径: " TARGET_DIR
fi

# ── 验证目标目录 ──
if [ -z "$TARGET_DIR" ]; then
    red "[错误] 未指定安装目录。"
    exit 1
fi

if [ ! -f "$TARGET_DIR/docker-compose.yml" ]; then
    red "[错误] $TARGET_DIR 不是有效的 PocketClaw 目录"
    echo "       缺少 docker-compose.yml"
    exit 1
fi

# ── 读取版本 ──
CUR_VERSION=$(cat "$TARGET_DIR/VERSION" 2>/dev/null || echo "unknown")
NEW_VERSION=$(cat "$PAYLOAD_DIR/VERSION" 2>/dev/null || echo "unknown")

echo ""
echo "============================================"
echo "  安装目录: $TARGET_DIR"
echo "  当前版本: v${CUR_VERSION}"
echo "  更新至:   v${NEW_VERSION}"
echo "============================================"
echo ""

# ── 安全：手动安装包的来源校验 ──
# 此脚本会用 _payload 里的文件覆盖你的 scripts/、docker-compose.yml 等（下次启动即执行）。
# 若随包提供了对应的签名 ZIP（update.zip + update.zip.sig），用「现有安装」里钉死的公钥验签
# （而非 payload 里的，避免攻击者连公钥一起替换）；否则明确提示来源信任要求。
SIGNED_ZIP=""
for z in "$SCRIPT_DIR/update.zip" "$SCRIPT_DIR/../PocketClaw-update.zip" "$PAYLOAD_DIR/../update.zip"; do
    [ -f "$z" ] && [ -f "${z}.sig" ] && { SIGNED_ZIP="$z"; break; }
done
if [ -n "$SIGNED_ZIP" ] && [ -f "$TARGET_DIR/scripts/sign-release.sh" ] && [ -f "$TARGET_DIR/config/release-signing.pub" ]; then
    if bash "$TARGET_DIR/scripts/sign-release.sh" verify "$SIGNED_ZIP"; then
        green "[安全] 更新包签名验证通过。"
    else
        red "[安全] 更新包签名验证失败，已中止安装。"
        exit 1
    fi
else
    yellow "[安全提示] 这是一个手动分发的更新包，未随附可验证的签名。"
    echo "          安装它等于信任提供者：它会覆盖可执行脚本并在下次启动时运行。"
    echo "          请仅安装来自你信任来源（官方 pocketclaw.cn / 本人）的更新包。"
fi

read -rp "确认安装更新? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "已取消。"
    exit 0
fi

echo ""

# ── [1/4] 停止容器 ──
yellow "[1/4] 检查并停止运行中的容器..."
run_compose -f "$TARGET_DIR/docker-compose.yml" down 2>/dev/null || true
echo "  [OK] 容器已停止（或未在运行）"
echo ""

# ── [2/4] 创建回滚备份 ──
ROLLBACK_DIR="$TARGET_DIR/data/_rollback_v${CUR_VERSION}"
yellow "[2/4] 创建回滚备份: data/_rollback_v${CUR_VERSION}/"
mkdir -p "$ROLLBACK_DIR"

# 备份根目录文件
for f in docker-compose.yml Dockerfile.custom VERSION README.md 注意事项.md \
         QUICKSTART_WINDOWS.md .env.example .gitignore; do
    [ -f "$TARGET_DIR/$f" ] && cp "$TARGET_DIR/$f" "$ROLLBACK_DIR/" 2>/dev/null || true
done

# 备份 scripts/
if [ -d "$TARGET_DIR/scripts" ]; then
    cp -r "$TARGET_DIR/scripts" "$ROLLBACK_DIR/" 2>/dev/null || true
fi

# 备份 config/openclaw.json
if [ -f "$TARGET_DIR/config/openclaw.json" ]; then
    mkdir -p "$ROLLBACK_DIR/config"
    cp "$TARGET_DIR/config/openclaw.json" "$ROLLBACK_DIR/config/" 2>/dev/null || true
fi

echo "  [OK] 回滚备份已创建"
echo ""

# ── [3/4] 安装更新 ──
yellow "[3/4] 正在安装更新..."

# 安装更新：只更新项目文件，保留用户数据
# 排除目录: secrets data .env openclaw-src config/workspace .DS_Store

if command -v rsync &>/dev/null; then
    rsync -a \
        --exclude='secrets/' \
        --exclude='data/' \
        --exclude='.env' \
        --exclude='openclaw-src/' \
        --exclude='config/workspace/' \
        --exclude='.DS_Store' \
        --exclude='._*' \
        "$PAYLOAD_DIR/" "$TARGET_DIR/"
else
    yellow "  [信息] 未找到 rsync，使用 cp 方式安装..."
    # 复制根目录文件
    for f in "$PAYLOAD_DIR"/*; do
        bn=$(basename "$f")
        case "$bn" in secrets|data|openclaw-src|.DS_Store) continue ;; esac
        if [ -f "$f" ] && [ "$bn" != ".env" ]; then
            cp -f "$f" "$TARGET_DIR/"
        elif [ -d "$f" ]; then
            if [ "$bn" = "config" ]; then
                # config: 只复制 openclaw.json，不覆盖 workspace/
                [ -f "$f/openclaw.json" ] && cp -f "$f/openclaw.json" "$TARGET_DIR/config/"
            else
                cp -Rf "$f" "$TARGET_DIR/"
            fi
        fi
    done
    # 复制隐藏文件
    for f in "$PAYLOAD_DIR"/.[!.]*; do
        [ -e "$f" ] || continue
        bn=$(basename "$f")
        case "$bn" in .env|.DS_Store) continue ;; esac
        cp -f "$f" "$TARGET_DIR/"
    done
fi

echo "  [OK] 所有更新文件已安装"
echo ""

# ── [4/4] 完成 ──
green "╔══════════════════════════════════════╗"
green "║   [OK] 更新安装成功!                 ║"
green "║   v${CUR_VERSION} → v${NEW_VERSION}"
green "╚══════════════════════════════════════╝"
echo ""
echo "  回滚备份: $ROLLBACK_DIR"
echo "  如遇问题，将备份文件复制回原目录即可回滚。"
echo ""

read -rp "是否立即启动 PocketClaw? (y/N): " RESTART
if [[ "$RESTART" =~ ^[Yy]$ ]]; then
    echo ""
    yellow "[信息] 正在启动..."
    bash "$TARGET_DIR/scripts/start.sh"
else
    echo ""
    echo "下次启动: bash scripts/start.sh"
fi
