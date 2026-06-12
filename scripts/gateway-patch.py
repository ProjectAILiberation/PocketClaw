#!/usr/bin/env python3
"""
PocketClaw Gateway Route Injector

Patches OpenClaw's gateway HTTP handler to serve custom static files
(e.g. mobile.html) before the control-ui SPA handler intercepts them.

Why this is needed:
  OpenClaw's gateway dispatches HTTP requests through an ordered list of
  "request stages" (runGatewayHttpRequestStages). The control-ui stage runs
  last and returns index.html for every unmatched path (SPA behavior).
  This patch unshifts a stage to the FRONT of that list so our custom files
  are served directly from disk before control-ui can swallow them.

Compatibility note (2026.6 rewrite):
  Up to OpenClaw 2026.3.x the handler lived in dist/gateway-cli-*.js and used
  an `if (canvasHost) {` anchor. From the 2026.4+ rewrite it lives in
  dist/server.impl-*.js and uses the requestStages dispatcher. This script now
  locates the file by the dispatcher call rather than by filename, so it keeps
  working across dist hash changes. If OpenClaw renames the dispatcher again,
  patch_file() returns False and main() exits non-zero — the Dockerfile MUST
  treat that as a hard build failure (no `|| true`).

Usage:
  GW_DIR=/path/to/dist CONTROL_UI_DIR=/path/to/control-ui python3 gateway-patch.py
"""
import os, sys, glob

# The injected route prints status with emoji. Some build/console encodings
# (e.g. Windows GBK) cannot encode those code points and would crash the script
# AFTER a successful patch, corrupting the exit code. Force a lossy UTF-8 stream
# so output can never change the success/failure result.
for _stream in ("stdout", "stderr"):
    try:
        getattr(sys, _stream).reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

# Marker used both for the injected stage name and the idempotency check.
MARKER = "pocketclaw-custom-files"

# Anchor: the dispatcher call that runs the ordered request stages. We inject a
# `requestStages.unshift(...)` immediately before it. At this point requestPath,
# req and res are all in lexical scope inside handleRequest().
DISPATCH_ANCHOR = "if (await runGatewayHttpRequestStages(requestStages)) return;"
DISPATCH_ANCHOR_ALT = "await runGatewayHttpRequestStages(requestStages)"


def find_gateway_files(gw_dir):
    """Find dist JS files that contain the gateway request dispatcher."""
    candidates = glob.glob(os.path.join(gw_dir, "*.js"))
    hits = []
    for path in candidates:
        try:
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
        except (OSError, UnicodeDecodeError):
            continue
        if "runGatewayHttpRequestStages(requestStages)" in content:
            hits.append(path)
    return hits


def build_injection_code(ui_dir):
    """Build a single-line JS snippet that unshifts a custom-files stage.

    Kept on one logical line (no reliance on surrounding indentation) so it
    survives whatever whitespace the minified/bundled handler uses.
    """
    escaped_dir = ui_dir.replace("\\", "\\\\").replace("'", "\\'")
    csp = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "img-src 'self' data: https:; "
        "font-src 'self' https://fonts.gstatic.com; "
        "connect-src 'self' ws: wss:; "
        "base-uri 'none'; object-src 'none'; frame-ancestors 'none'"
    )
    return (
        "requestStages.unshift({ "
        f"name: '{MARKER}', continueOnError: true, run: async () => {{ "
        "const _pcFiles = { '/mobile.html': 'text/html; charset=utf-8' }; "
        "const _pcMime = _pcFiles[requestPath]; "
        "if (_pcMime && requestPath.indexOf('..') === -1 && requestPath.indexOf('\\\\') === -1) { "
        "const _pcFs = await import('node:fs'); "
        f"const _pcData = _pcFs.default.readFileSync('{escaped_dir}' + requestPath); "
        "res.writeHead(200, { 'Content-Type': _pcMime, 'Cache-Control': 'no-cache', "
        f"'Content-Security-Policy': \"{csp}\" }}); "
        "res.end(_pcData); return true; "
        "} "
        "if (requestPath === '/api-info') { "
        "try { const _pcFs = await import('node:fs'); "
        "const _pcData = _pcFs.default.readFileSync('/home/node/.openclaw/api-status.json'); "
        "res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' }); "
        "res.end(_pcData); return true; "
        "} catch (_pcErr) { "
        "res.writeHead(200, { 'Content-Type': 'application/json' }); res.end('{}'); return true; "
        "} } "
        "return false; "
        "} });\n\t\t\t"
    )


def patch_file(gw_file, inject_code):
    """Patch a single dist JS file. Returns True on success."""
    basename = os.path.basename(gw_file)
    try:
        with open(gw_file, "r", encoding="utf-8") as f:
            content = f.read()
    except (PermissionError, OSError) as e:
        print(f"  ⚠️  无法读取 {basename}: {e}")
        return False

    # Idempotency: already injected.
    if MARKER in content:
        return True

    anchor = DISPATCH_ANCHOR
    idx = content.find(anchor)
    if idx == -1:
        # Fallback: inject before the bare dispatcher call (any wrapping form).
        idx = content.find(DISPATCH_ANCHOR_ALT)
        if idx == -1:
            print(f"  ⚠️  {basename}: 未找到 requestStages 派发点（OpenClaw 可能又改了结构）")
            return False
        anchor = DISPATCH_ANCHOR_ALT
        # Anchor on the start of the statement, not mid-expression: walk back to
        # the preceding "if (" if present so we insert before the whole `if`.
        if_idx = content.rfind("if (", max(0, idx - 16), idx)
        if if_idx != -1:
            idx = if_idx

    # Backup once.
    backup_path = gw_file + ".pc-backup"
    if not os.path.exists(backup_path):
        try:
            with open(backup_path, "w", encoding="utf-8") as bf:
                bf.write(content)
        except OSError:
            pass  # backup failure must not block injection

    new_content = content[:idx] + inject_code + content[idx:]

    # Self-check: the marker must actually be present in what we are about to write.
    if MARKER not in new_content:
        print(f"  ⚠️  {basename}: 注入自检失败（marker 未出现）")
        return False

    try:
        with open(gw_file, "w", encoding="utf-8") as f:
            f.write(new_content)
    except (PermissionError, OSError) as e:
        print(f"  ⚠️  无法写入 {basename}: {e}")
        return False

    # Read-back self-check: confirm the marker landed on disk.
    try:
        with open(gw_file, "r", encoding="utf-8") as f:
            if MARKER not in f.read():
                print(f"  ⚠️  {basename}: 写回后未找到 marker，注入未生效")
                return False
    except OSError:
        return False

    return True


def main():
    gw_dir = os.environ.get("GW_DIR", "")
    ui_dir = os.environ.get("CONTROL_UI_DIR", "")

    if not gw_dir or not ui_dir:
        print("  ⚠️  缺少 GW_DIR 或 CONTROL_UI_DIR 环境变量")
        sys.exit(1)

    gw_files = find_gateway_files(gw_dir)
    if not gw_files:
        print(f"  ⚠️  未找到包含 runGatewayHttpRequestStages 的 dist 文件 (目录: {gw_dir})")
        sys.exit(1)

    inject_code = build_injection_code(ui_dir)
    patched = False

    for gw_file in gw_files:
        if patch_file(gw_file, inject_code):
            patched = True

    if patched:
        print("  ✅ Gateway 自定义路由已注入（requestStages）")
    else:
        print("  ⚠️  Gateway 路由注入失败（mobile.html 将无法访问）")
        sys.exit(1)


if __name__ == "__main__":
    main()
