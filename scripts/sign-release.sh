#!/usr/bin/env bash
# ============================================================
# sign-release.sh  —— 发布包签名与校验工具 (D6)
#
# 使用 Ed25519 对发布 ZIP 进行签名，用户可验证包的真实性。
# 比 GPG 更简单，无需 keyserver。
#
# 用法:
#   bash scripts/sign-release.sh sign   <file.zip>   # 签名
#   bash scripts/sign-release.sh verify <file.zip>    # 验证
#   bash scripts/sign-release.sh keygen               # 生成密钥对
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 私钥仅存于 secrets/（已 .gitignore，维护者离线保管，绝不分发）。
PRIVATE_KEY="$PROJECT_DIR/secrets/sign.key"
# 公钥「钉死」在仓库内的固定路径并随产品分发——验证时只信任此处的公钥，
# 绝不从被验证的下载包里读取公钥（否则攻击者重打包时塞自己的公钥即可绕过验签）。
PUBLIC_KEY="$PROJECT_DIR/config/release-signing.pub"

# ── 帮助 ──
usage() {
    echo "用法:"
    echo "  bash scripts/sign-release.sh keygen                # 生成 Ed25519 密钥对"
    echo "  bash scripts/sign-release.sh sign   <file.zip>     # 对文件签名"
    echo "  bash scripts/sign-release.sh verify <file.zip>     # 验证签名"
    echo ""
    echo "签名文件: <file>.sig  (与原文件同目录)"
    echo "公钥文件: secrets/sign.pub"
    exit 1
}

# ── 检查 openssl 版本（需要 1.1.1+ 支持 Ed25519）──
check_openssl() {
    if ! command -v openssl &>/dev/null; then
        echo "[错误] 未找到 openssl，请先安装"
        exit 1
    fi
    local VER
    VER=$(openssl version 2>/dev/null | awk '{print $2}')
    echo "[信息] OpenSSL 版本: $VER"
}

# ── 生成密钥对 ──
do_keygen() {
    check_openssl
    
    if [ -f "$PRIVATE_KEY" ]; then
        echo "[警告] 私钥已存在: $PRIVATE_KEY"
        printf "  覆盖？(y/N): "
        read -r CONFIRM
        [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && exit 0
    fi

    mkdir -p "$PROJECT_DIR/secrets" "$PROJECT_DIR/config"

    # 生成 Ed25519 私钥
    openssl genpkey -algorithm Ed25519 -out "$PRIVATE_KEY" 2>/dev/null
    chmod 600 "$PRIVATE_KEY"

    # 导出公钥到「钉死」的固定路径（此文件应提交进 Git 并随产品分发）
    openssl pkey -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" 2>/dev/null

    echo ""
    echo "[OK] Ed25519 密钥对已生成"
    echo "  私钥: $PRIVATE_KEY  (⚠️ 离线安全保管，绝不提交 Git / 绝不进发行包)"
    echo "  公钥: $PUBLIC_KEY   (✅ 请 git add 提交此文件——它是验签的唯一信任锚)"
    echo ""
    echo "公钥内容:"
    cat "$PUBLIC_KEY"
    echo ""
    echo "下一步（让签名更新生效）:"
    echo "  1) git add config/release-signing.pub && git commit  # 固定信任锚"
    echo "  2) 发布时对 ZIP 执行: bash scripts/sign-release.sh sign <zip>"
    echo "  3) 把生成的 <zip>.sig 一并上传到下载源，与 ZIP 同目录同名"
}

# ── 签名 ──
do_sign() {
    local FILE=$1
    check_openssl
    
    if [ ! -f "$FILE" ]; then
        echo "[错误] 文件不存在: $FILE"
        exit 1
    fi
    
    if [ ! -f "$PRIVATE_KEY" ]; then
        echo "[错误] 私钥不存在: $PRIVATE_KEY"
        echo "  请先运行: bash scripts/sign-release.sh keygen"
        exit 1
    fi
    
    local SIG_FILE="${FILE}.sig"
    local HASH_FILE="${FILE}.sha256"
    
    # 计算 SHA-256
    if command -v sha256sum &>/dev/null; then
        sha256sum "$FILE" | awk '{print $1}' > "$HASH_FILE"
    else
        shasum -a 256 "$FILE" | awk '{print $1}' > "$HASH_FILE"
    fi
    
    # Ed25519 签名
    openssl pkeyutl -sign -inkey "$PRIVATE_KEY" \
        -rawin -in "$FILE" \
        -out "$SIG_FILE" 2>/dev/null
    
    local FILE_SIZE
    FILE_SIZE=$(ls -lh "$FILE" | awk '{print $5}')
    local SIG_SIZE
    SIG_SIZE=$(ls -lh "$SIG_FILE" | awk '{print $5}')
    
    echo ""
    echo "[OK] 签名完成"
    echo "  文件:     $FILE ($FILE_SIZE)"
    echo "  SHA-256:  $(cat "$HASH_FILE")"
    echo "  签名:     $SIG_FILE ($SIG_SIZE)"
    echo ""
    echo "验证命令:"
    echo "  bash scripts/sign-release.sh verify $FILE"
}

# ── 验证 ──
do_verify() {
    local FILE=$1
    check_openssl
    
    if [ ! -f "$FILE" ]; then
        echo "[错误] 文件不存在: $FILE"
        exit 1
    fi
    
    local SIG_FILE="${FILE}.sig"

    echo "验证文件: $FILE"

    # 信任锚：只用钉死在仓库内的公钥。缺失即视为「未配置签名更新」，硬失败。
    if [ ! -f "$PUBLIC_KEY" ] || ! grep -q "BEGIN PUBLIC KEY" "$PUBLIC_KEY" 2>/dev/null; then
        echo "[错误] 未找到有效的钉死公钥: $PUBLIC_KEY"
        echo "       维护者尚未启用签名更新（运行 sign-release.sh keygen 并提交公钥）。"
        echo "       出于安全，拒绝验证未签名的包。"
        return 2   # 2 = 未配置签名（调用方据此区分「未启用」与「验签失败」）
    fi

    # 签名缺失 = 硬失败（绝不「无签名即放行」）。
    if [ ! -f "$SIG_FILE" ]; then
        echo "[错误] 缺少签名文件: $SIG_FILE"
        echo "       未签名的包一律拒绝安装。"
        return 1
    fi

    # 验证 Ed25519 签名（这是唯一的真实性来源；SHA-256 仅作完整性辅助、不提供真实性）。
    if openssl pkeyutl -verify -pubin -inkey "$PUBLIC_KEY" \
        -rawin -in "$FILE" -sigfile "$SIG_FILE" >/dev/null 2>&1; then
        echo "  签名:     ✅ 通过"
        echo "[OK] 验证通过 — 文件来自可信发布者且未被篡改"
        return 0
    else
        echo "  签名:     ❌ 失败"
        echo "[错误] 签名验证失败 — 文件可能被篡改或来源不可信！拒绝安装。"
        return 1
    fi
}

# ── 主入口 ──
ACTION="${1:-}"
case "$ACTION" in
    keygen)
        do_keygen
        ;;
    sign)
        [ -z "${2:-}" ] && usage
        do_sign "$2"
        ;;
    verify)
        [ -z "${2:-}" ] && usage
        do_verify "$2"
        ;;
    *)
        usage
        ;;
esac
