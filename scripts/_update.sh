#!/usr/bin/env bash
# ============================================================
# _update.sh  —— 版本更新检查与安装模块
# 由 start.sh 通过 source 引入
# ============================================================

# ── 检查并安装更新 ──
# 参数: $1=PROJECT_DIR  返回: POCKETCLAW_VERSION 可能被更新
check_and_update() {
    local PROJECT_DIR=$1
    POCKETCLAW_VERSION=$(cat "$PROJECT_DIR/VERSION" 2>/dev/null || echo "unknown")
    echo "[信息] 正在检查更新..."

    local VERSION_API="https://pocketclaw.cn/downloads/version.json"
    local VERSION_API_BACKUP="https://raw.githubusercontent.com/tinqiao-oss/PocketClaw/main/version.json"
    local LATEST_VER="" DOWNLOAD_URL="" DOWNLOAD_URL_BACKUP="" VERSION_JSON=""

    if command -v curl &>/dev/null; then
        VERSION_JSON=$(curl -sf --connect-timeout 5 "$VERSION_API" 2>/dev/null || \
                       curl -sf --connect-timeout 5 "$VERSION_API_BACKUP" 2>/dev/null || true)
        if [ -n "$VERSION_JSON" ]; then
            # 优先用 python3 解析 JSON（健壮），回退到 grep+sed
            if command -v python3 &>/dev/null; then
                LATEST_VER=$(echo "$VERSION_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('latest', d.get('version', '')))" 2>/dev/null || true)
                DOWNLOAD_URL=$(echo "$VERSION_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('download_url', d.get('cos_url', '')))" 2>/dev/null || true)
                DOWNLOAD_URL_BACKUP=$(echo "$VERSION_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('download_url_backup', ''))" 2>/dev/null || true)
            else
                LATEST_VER=$(echo "$VERSION_JSON" | grep -o '"latest"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
                [ -z "$LATEST_VER" ] && LATEST_VER=$(echo "$VERSION_JSON" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
                DOWNLOAD_URL=$(echo "$VERSION_JSON" | grep -o '"download_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
                [ -z "$DOWNLOAD_URL" ] && DOWNLOAD_URL=$(echo "$VERSION_JSON" | grep -o '"cos_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
                DOWNLOAD_URL_BACKUP=$(echo "$VERSION_JSON" | grep -o '"download_url_backup"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
            fi
        fi
    fi

    if [ -z "$LATEST_VER" ]; then
        echo "[信息] 无法获取版本信息（网络问题），跳过检查"
        return 0
    fi

    if [ "$LATEST_VER" = "$POCKETCLAW_VERSION" ]; then
        echo "[OK] 当前已是最新版本 v${POCKETCLAW_VERSION}"
        return 0
    fi

    echo ""
    echo "============================================"
    echo "  [更新] 发现新版本 v${LATEST_VER}"
    echo "         当前版本 v${POCKETCLAW_VERSION}"
    echo "============================================"
    echo ""
    echo "  （更新不会影响您的私有数据和配置）"
    printf "  是否一键更新？(y/N): "
    read -r UPDATE_CHOICE
    if [ "$UPDATE_CHOICE" != "y" ] && [ "$UPDATE_CHOICE" != "Y" ]; then
        echo "  [信息] 已跳过更新，可随时访问 pocketclaw.cn 下载"
        echo ""
        return 0
    fi

    _do_update "$PROJECT_DIR" "$DOWNLOAD_URL" "$DOWNLOAD_URL_BACKUP"
}

# ── 下载地址白名单校验 ──
# 只允许 HTTPS + 固定可信主机，拒绝 http:// 与任意主机（version.json 由服务器控制，
# 不加白名单则等于让服务器决定从哪里下载并安装可执行脚本）。
_url_is_allowed() {
    local url="$1"
    case "$url" in
        https://pocketclaw.cn/*) return 0 ;;
        https://*.pocketclaw.cn/*) return 0 ;;
        https://github.com/tinqiao-oss/PocketClaw/*) return 0 ;;
        https://raw.githubusercontent.com/tinqiao-oss/PocketClaw/*) return 0 ;;
        https://objects.githubusercontent.com/*) return 0 ;;  # GitHub release 资产重定向目标
        *) return 1 ;;
    esac
}

# ── 执行更新 ──
_do_update() {
    local PROJECT_DIR=$1
    local DOWNLOAD_URL=$2
    local DOWNLOAD_URL_BACKUP=$3

    echo ""
    echo "[更新] 正在下载更新包..."
    local UPDATE_ZIP="/tmp/PocketClaw-update.zip"
    local UPDATE_SIG="/tmp/PocketClaw-update.zip.sig"
    local UPDATE_DIR="/tmp/PocketClaw-update"
    local DL_OK=0 USED_URL=""

    # 选择一个通过白名单校验的下载地址（主源优先，回退备用源）
    local CAND
    for CAND in "$DOWNLOAD_URL" "$DOWNLOAD_URL_BACKUP"; do
        [ -z "$CAND" ] && continue
        if ! _url_is_allowed "$CAND"; then
            echo "[安全] 拒绝不可信的下载地址（非白名单/非 HTTPS）：$CAND"
            continue
        fi
        # 注意：不使用 -L 跟随跨域重定向到任意主机；GitHub 资产的重定向目标已在白名单内，
        # 故仅对 github.com 源单独允许一次重定向。
        local CURL_OPTS=(-sf --connect-timeout 30 --proto '=https' --tlsv1.2)
        case "$CAND" in https://github.com/*) CURL_OPTS+=(-L) ;; esac
        if curl "${CURL_OPTS[@]}" "$CAND" -o "$UPDATE_ZIP" 2>/dev/null; then
            DL_OK=1; USED_URL="$CAND"
            # 同名 .sig（与 ZIP 同目录同名 + .sig）
            curl "${CURL_OPTS[@]}" "${CAND}.sig" -o "$UPDATE_SIG" 2>/dev/null || true
            break
        fi
    done

    if [ "$DL_OK" -ne 1 ]; then
        echo "[错误] 下载失败或地址不可信，请检查网络或手动访问 pocketclaw.cn 下载"
        rm -f "$UPDATE_ZIP" "$UPDATE_SIG"
        return 1
    fi

    # ── 强制验签（修复审计 Critical #1：更新链路零验证）──
    # 在解压/覆盖任何文件之前，用钉死在仓库内的公钥验证 Ed25519 签名，fail-closed。
    echo "[更新] 正在验证更新包签名..."
    local _vrc=0
    bash "$PROJECT_DIR/scripts/sign-release.sh" verify "$UPDATE_ZIP" || _vrc=$?
    if [ "$_vrc" -eq 2 ]; then
        echo "[安全] 维护者尚未启用签名更新，出于安全已禁用自动安装。"
        echo "       请前往 pocketclaw.cn 手动下载并自行核对来源后再更新。"
        rm -f "$UPDATE_ZIP" "$UPDATE_SIG"; rm -rf "$UPDATE_DIR"
        return 1
    elif [ "$_vrc" -ne 0 ]; then
        echo "[安全] 更新包验签失败，已中止安装并删除下载文件（疑似被篡改或来源不可信）。"
        rm -f "$UPDATE_ZIP" "$UPDATE_SIG"; rm -rf "$UPDATE_DIR"
        return 1
    fi
    echo "[更新] 签名验证通过（来源：$USED_URL），正在解压..."
    rm -rf "$UPDATE_DIR"
    unzip -qo "$UPDATE_ZIP" -d "$UPDATE_DIR" 2>/dev/null || {
        python3 -c "import zipfile; zipfile.ZipFile('$UPDATE_ZIP').extractall('$UPDATE_DIR')" 2>/dev/null
    }

    local PAYLOAD=""
    if [ -d "$UPDATE_DIR/PocketClaw" ]; then
        PAYLOAD="$UPDATE_DIR/PocketClaw"
    else
        for d in "$UPDATE_DIR"/*/; do
            [ -f "${d}VERSION" ] && PAYLOAD="$d" && break
        done
    fi

    if [ -z "$PAYLOAD" ]; then
        echo "[错误] 更新包格式异常，请手动更新"
        rm -rf "$UPDATE_DIR" "$UPDATE_ZIP" "$UPDATE_SIG"
        return 1
    fi

    echo "[更新] 正在安装更新..."
    # 复制根目录文件（不覆盖 .env）
    for f in "$PAYLOAD"/*; do
        [ -f "$f" ] && bn=$(basename "$f") && [ "$bn" != ".env" ] && cp -f "$f" "$PROJECT_DIR/" 2>/dev/null
    done
    [ -d "$PAYLOAD/scripts" ] && cp -rf "$PAYLOAD/scripts/"* "$PROJECT_DIR/scripts/" 2>/dev/null
    [ -d "$PAYLOAD/config" ] && {
        for cf in "$PAYLOAD/config"/*; do
            [ -f "$cf" ] && cp -f "$cf" "$PROJECT_DIR/config/" 2>/dev/null
        done
    }
    [ -d "$PAYLOAD/config/workspace" ] && {
        for wf in "$PAYLOAD/config/workspace"/*.md; do
            [ -f "$wf" ] && cp -f "$wf" "$PROJECT_DIR/config/workspace/" 2>/dev/null
        done
    }
    [ -d "$PAYLOAD/config/workspace/skills" ] && cp -rf "$PAYLOAD/config/workspace/skills/"* "$PROJECT_DIR/config/workspace/skills/" 2>/dev/null

    local NEW_VER
    NEW_VER=$(cat "$PAYLOAD/VERSION" 2>/dev/null || echo "?")
    POCKETCLAW_VERSION="$NEW_VER"
    rm -f "$PROJECT_DIR/data/.build_hash"

    echo ""
    echo "============================================"
    echo "  [OK] 更新完成! v${POCKETCLAW_VERSION}"
    echo "       正在继续启动新版本..."
    echo "============================================"
    echo ""
    rm -rf "$UPDATE_DIR" "$UPDATE_ZIP" "$UPDATE_SIG"
}
