#!/usr/bin/env bash
# ============================================================
# skill-check.sh — Skill 文件安全扫描器
# 扫描 skills 目录中的 .md 文件，检测危险模式并阻止可疑文件
# 用法: bash scripts/skill-check.sh [skills_dir]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# 安全（修复审计 High：原默认扫 data/skills，但实际生效的 Skill 在 config/workspace/skills，
# 导致这道"L5 Skill 安全扫描"形同虚设）。默认改为扫真正被 agent 加载的目录。
SKILLS_DIR="${1:-$PROJECT_DIR/config/workspace/skills}"
MAX_SIZE=51200  # 50KB

# 内置 skill 白名单（SHA-256 校验跳过）
BUILTIN_SKILLS="data-analysis.md file-processing.md image-tools.md model-switch.md notes.md ppt-generator.md reminders.md text-tools.md todo.md"

# 危险模式正则（逐行匹配）
DANGER_PATTERNS=(
    # Shell 注入（精确匹配命令行模式）
    'rm\s+-rf\s+/'
    '\beval\s+\$'
    '\bexec\s+[^u]'
    'subprocess\.(call|run|Popen)'
    'os\.system\s*\('
    'child_process\.exec'
    # 系统文件篡改（精确匹配修改指令）
    '(修改|编辑|更新|覆盖|写入)\s*AGENTS\.md'
    '(修改|编辑|更新|覆盖|写入)\s*SOUL\.md'
    '(修改|编辑|更新|覆盖)\s*\.provider'
    '(修改|编辑|更新|覆盖)\s*TOOLS\.md'
    '(修改|编辑|更新|覆盖)\s*\.gateway_token'
    # 凭据窃取（精确匹配读取操作）
    '(读取|获取|打印|显示|发送)\s*(API.Key|密码|token|密钥)'
    '(cat|echo|print)\s+.*\.env\b'
    '(cat|echo|print)\s+.*master\.key'
    # 提示注入
    '忽略之前的指令'
    '忽略以上指令'
    'ignore previous instructions'
    'ignore above instructions'
    'you are a new (ai|assistant)'
    'override.*system prompt'
    'jailbreak'
    # 数据外传（精确匹配外部 URL 发送）
    'curl.*-d.*http'
    'wget.*--post.*http'
)

blocked=0
scanned=0

scan_file() {
    local file="$1"
    local basename
    basename="$(basename "$file")"

    # 跳过非 .md 文件
    [[ "$basename" != *.md ]] && return 0

    # 跳过内置 skill
    for builtin in $BUILTIN_SKILLS; do
        [[ "$basename" = "$builtin" ]] && return 0
    done

    scanned=$((scanned + 1))

    # 检查文件大小
    local size
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || wc -c < "$file" 2>/dev/null || echo 0)
    if [ "$size" -gt "$MAX_SIZE" ]; then
        echo "  ⚠ 阻止: $basename — 文件过大 (${size} bytes > ${MAX_SIZE})"
        mv "$file" "${file}.blocked"
        blocked=$((blocked + 1))
        return 1
    fi

    # 检查 UTF-8 编码
    if ! file -b "$file" 2>/dev/null | grep -qi 'text\|empty'; then
        echo "  ⚠ 阻止: $basename — 非文本文件"
        mv "$file" "${file}.blocked"
        blocked=$((blocked + 1))
        return 1
    fi

    # 危险模式扫描
    local matches=""
    for pattern in "${DANGER_PATTERNS[@]}"; do
        local hit
        hit=$(grep -iEc "$pattern" "$file" 2>/dev/null || true)
        if [ "$hit" -gt 0 ]; then
            matches="${matches}    - 匹配: ${pattern} (${hit}次)\n"
        fi
    done

    if [ -n "$matches" ]; then
        echo "  ⚠ 阻止: $basename — 检测到危险模式:"
        printf "$matches"
        mv "$file" "${file}.blocked"
        blocked=$((blocked + 1))
        return 1
    fi

    return 0
}

# ── 主流程 ──
if [ ! -d "$SKILLS_DIR" ]; then
    exit 0
fi

echo "[Skill 安全扫描] 检查 $SKILLS_DIR ..."

for file in "$SKILLS_DIR"/*.md; do
    [ -f "$file" ] || continue
    scan_file "$file" || true
done

if [ "$scanned" -eq 0 ]; then
    echo "  ✅ 无需扫描（仅内置 Skill）"
elif [ "$blocked" -eq 0 ]; then
    echo "  ✅ 已扫描 ${scanned} 个自定义 Skill，全部安全"
else
    echo "  ⚠ 已阻止 ${blocked}/${scanned} 个可疑 Skill 文件"
    echo "  被阻止的文件已重命名为 .blocked，可手动审查后删除 .blocked 后缀恢复"
fi
