#!/usr/bin/env python3
"""
build_zip.py — PocketClaw ZIP 构建工具
- 使用 Python zipfile 确保 UTF-8 EFS 标志（Windows 解压不乱码）
- 外套 PocketClaw/ 顶层目录（可直接拖出使用）
- 排除 .git、.env、data/sessions 等运行时文件
"""
import os
import sys
import zipfile
import time

# 项目根目录
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.dirname(SCRIPT_DIR)  # PocketClaw/
PROJECT_DIR = os.path.dirname(SRC_DIR)  # USB_OpenClaw_Project/

# 读取版本号
version_file = os.path.join(SRC_DIR, "VERSION")
if not os.path.exists(version_file):
    print(f"ERROR: VERSION file not found at {version_file}")
    sys.exit(1)

with open(version_file, "r") as f:
    version = f.read().strip()

ZIP_NAME = f"PocketClaw-v{version}.zip"
ZIP_PATH = os.path.join(PROJECT_DIR, ZIP_NAME)

# 排除规则
EXCLUDE_DIRS = {
    ".git",
    "data/sessions",
    "data/logs",
    "data/credentials",
    "data/skills",
    "__pycache__",
    ".github",
    # 安全：绝不把 secrets/ 下的任何真实文件打进发行包
    # （含加密主密钥 master.key、Ed25519 签名私钥 sign.key、维护者的 .env.encrypted）。
    # build 末尾仍会补一个空的 secrets/ 占位目录（见下方 empty_dir 列表）。
    "secrets",
}

EXCLUDE_FILES = {
    ".env",
    ".DS_Store",
    ".host_ip",
    ".gateway_token",
    # 运行时明文凭据 / 状态：绝不分发（API key 明文、已绑定提供商）
    ".provider",
    ".bound_providers",
    ".build_hash",
    ".gitignore",
    # 开发备忘（.gitignore 注明不参与分发，但 git 忽略不等于打包排除）
    "开发备忘.md",
}

EXCLUDE_EXTENSIONS = {
    ".pyc",
    ".pyo",
    # 纵深防御：任何密钥/明文都不进包
    ".key",
    ".pem",
    ".encrypted",
    ".decrypted",
    ".pc-backup",
}


def should_exclude(rel_path):
    """检查文件是否应该排除"""
    parts = rel_path.replace("\\", "/").split("/")

    # 检查目录排除
    for exc_dir in EXCLUDE_DIRS:
        exc_parts = exc_dir.split("/")
        for i in range(len(parts) - len(exc_parts) + 1):
            if parts[i:i+len(exc_parts)] == exc_parts:
                return True

    # 检查文件名排除
    basename = os.path.basename(rel_path)
    if basename in EXCLUDE_FILES:
        return True

    # 检查扩展名排除
    _, ext = os.path.splitext(basename)
    if ext in EXCLUDE_EXTENSIONS:
        return True

    return False


def main():
    print(f"Building PocketClaw v{version} ZIP...")
    print(f"Source: {SRC_DIR}")
    print(f"Output: {ZIP_PATH}")

    file_count = 0
    total_size = 0

    with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(SRC_DIR):
            # 过滤目录（原地修改 dirs 会影响 os.walk 的遍历）
            dirs[:] = [d for d in dirs
                       if not should_exclude(os.path.relpath(os.path.join(root, d), SRC_DIR))]

            for filename in sorted(files):
                filepath = os.path.join(root, filename)
                rel_path = os.path.relpath(filepath, SRC_DIR)

                if should_exclude(rel_path):
                    continue

                # ZIP 内路径：PocketClaw/xxx
                arcname = os.path.join("PocketClaw", rel_path)
                # 统一使用正斜杠
                arcname = arcname.replace("\\", "/")

                # 创建 ZipInfo 手动设置 UTF-8 EFS 标志
                info = zipfile.ZipInfo(arcname)
                info.flag_bits |= 0x800  # UTF-8 EFS flag (bit 11)

                # 保留文件修改时间
                mtime = os.path.getmtime(filepath)
                info.date_time = time.localtime(mtime)[:6]

                # 设置压缩方式
                info.compress_type = zipfile.ZIP_DEFLATED

                # 设置外部属性（保留可执行权限）
                st = os.stat(filepath)
                info.external_attr = (st.st_mode & 0xFFFF) << 16

                try:
                    with open(filepath, "rb") as f:
                        data = f.read()
                except (PermissionError, OSError) as e:
                    print(f"  WARNING: Skipping {rel_path}: {e}")
                    continue

                zf.writestr(info, data)
                file_count += 1
                total_size += len(data)

        # 添加必要的空目录
        for empty_dir in ["data/sessions", "data/logs", "data/credentials", "data/skills",
                          "secrets"]:
            dir_path = f"PocketClaw/{empty_dir}/"
            info = zipfile.ZipInfo(dir_path)
            info.flag_bits |= 0x800
            info.external_attr = 0o40755 << 16  # directory
            zf.writestr(info, b"")

    zip_size = os.path.getsize(ZIP_PATH)
    print(f"\n  Files: {file_count}")
    print(f"  Original: {total_size / 1024:.0f} KB")
    print(f"  ZIP size: {zip_size / 1024:.0f} KB")
    print(f"\nVerifying UTF-8 EFS flags...")

    # 验证
    with zipfile.ZipFile(ZIP_PATH, "r") as zf:
        errors = []
        for info in zf.infolist():
            is_utf8 = bool(info.flag_bits & 0x800)
            has_nonascii = any(ord(c) > 127 for c in info.filename)
            if has_nonascii:
                print(f"  Non-ASCII: {info.filename} (UTF-8={is_utf8})")
                if not is_utf8:
                    errors.append(info.filename)
        # Check top-level structure
        top_entries = set()
        for info in zf.infolist():
            top = info.filename.split("/")[0]
            top_entries.add(top)
        if top_entries == {"PocketClaw"}:
            print(f"  Structure: PocketClaw/ wrapper - OK")
        else:
            print(f"  WARNING: Unexpected top-level entries: {top_entries}")

    if not errors:
        print(f"\n[OK] {ZIP_NAME} ({zip_size/1024:.0f} KB)")
    else:
        print(f"\n[ERROR] Non-ASCII files missing UTF-8 flag: {errors}")
        sys.exit(1)


if __name__ == "__main__":
    main()
