@echo off
setlocal EnableDelayedExpansion
REM ============================================================
REM update.bat  —— 检查 PocketClaw 更新 [Windows]
REM 用法: scripts\update.bat
REM ============================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "PROJECT_DIR=%CD%"

echo.
echo ======================================
echo    PocketClaw 检查更新
echo ======================================
echo.

REM --------------- 读取当前版本 ---------------
set "PC_VER=unknown"
if exist "%PROJECT_DIR%\VERSION" (
    set /p PC_VER=<"%PROJECT_DIR%\VERSION"
)
echo [信息] 当前版本 v!PC_VER!，正在检查更新...

REM --------------- 获取服务器版本信息 ---------------
set "VERSION_API=https://pocketclaw.cn/downloads/version.json"
set "VERSION_API_BACKUP=https://raw.githubusercontent.com/tinqiao-oss/PocketClaw/main/version.json"
set "LATEST_VER="
set "DOWNLOAD_URL="
set "DOWNLOAD_URL_BACKUP="
set "VER_JSON_FILE=%TEMP%\pocketclaw_ver.json"

REM 尝试主服务器
powershell -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{(New-Object Net.WebClient).DownloadFile('%VERSION_API%','%VER_JSON_FILE%')}catch{try{(New-Object Net.WebClient).DownloadFile('%VERSION_API_BACKUP%','%VER_JSON_FILE%')}catch{exit 1}}"

if not exist "%VER_JSON_FILE%" (
    echo [信息] 无法获取版本信息（网络问题），跳过检查
    popd
    exit /b 0
)

REM 解析 JSON
for /f "usebackq delims=" %%j in ("%VER_JSON_FILE%") do set "JSON_LINE=%%j"
del "%VER_JSON_FILE%" 2>nul

REM 提取 latest 版本号
for /f "tokens=2 delims=:, " %%a in ('echo !JSON_LINE! ^| findstr /i "latest"') do (
    set "LATEST_VER=%%~a"
)
if "!LATEST_VER!"=="" (
    for /f "tokens=2 delims=:, " %%a in ('echo !JSON_LINE! ^| findstr /i "version"') do (
        set "LATEST_VER=%%~a"
    )
)

REM 提取下载 URL
for /f "tokens=2 delims=, " %%a in ('echo !JSON_LINE! ^| findstr /i "download_url"') do (
    set "DOWNLOAD_URL=%%~a"
)

if "!LATEST_VER!"=="" (
    echo [信息] 无法解析版本信息，跳过检查
    popd
    exit /b 0
)

REM --------------- 版本比较 ---------------
if "!LATEST_VER!"=="!PC_VER!" (
    echo [OK] 当前已是最新版本 v!PC_VER!
    popd
    exit /b 0
)

echo.
echo ============================================
echo   [更新] 发现新版本 v!LATEST_VER!
echo          当前版本 v!PC_VER!
echo ============================================
echo.
echo   （更新不会影响您的私有数据和配置）
set /p "UPDATE_CHOICE=  是否一键更新？(y/N): "
if /i not "!UPDATE_CHOICE!"=="y" (
    echo   [信息] 已跳过更新，可随时访问 pocketclaw.cn 下载
    popd
    exit /b 0
)

echo.
echo [更新] 正在下载更新包...
set "UPDATE_ZIP=%TEMP%\PocketClaw-update.zip"
set "UPDATE_DIR=%TEMP%\PocketClaw-update"

if "!DOWNLOAD_URL!"=="" set "DOWNLOAD_URL=https://pocketclaw.cn/downloads/PocketClaw-v!LATEST_VER!.zip"

powershell -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{(New-Object Net.WebClient).DownloadFile('!DOWNLOAD_URL!','%UPDATE_ZIP%')}catch{exit 1}"

if not exist "%UPDATE_ZIP%" (
    echo [错误] 下载失败，请检查网络或手动访问 pocketclaw.cn 下载
    popd
    exit /b 1
)

echo [更新] 下载完成，正在解压...
if exist "%UPDATE_DIR%" rmdir /s /q "%UPDATE_DIR%"
REM --------------- 强制验签（修复审计 Critical #1：更新链路零验证） ---------------
REM 只信任仓库内钉死的公钥 config\release-signing.pub；验签失败/缺签名/未配置均拒绝安装。
set "PINNED_PUB=%PROJECT_DIR%\config\release-signing.pub"
set "UPDATE_SIG=%UPDATE_ZIP%.sig"
if not exist "!PINNED_PUB!" (
    echo [安全] 维护者尚未启用签名更新（config\release-signing.pub 缺失）。
    echo        出于安全已禁用安装未验证的包，请前往 pocketclaw.cn 手动下载并核对来源。
    del "%UPDATE_ZIP%" 2>nul
    popd
    exit /b 1
)
REM 定位 openssl（沿用 start.bat 的同款探测）
set "OPENSSL_BIN=openssl"
where openssl >nul 2>&1 || if exist "C:\Program Files\Git\usr\bin\openssl.exe" set "OPENSSL_BIN=C:\Program Files\Git\usr\bin\openssl.exe"
REM 下载同名 .sig（与 ZIP 同目录同名 + .sig）
powershell -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try{(New-Object Net.WebClient).DownloadFile('!DOWNLOAD_URL!.sig','%UPDATE_SIG%')}catch{exit 1}"
if not exist "%UPDATE_SIG%" (
    echo [安全] 未找到签名文件 .sig，未签名的包一律拒绝安装。
    del "%UPDATE_ZIP%" 2>nul
    popd
    exit /b 1
)
echo [更新] 正在验证更新包签名...
"!OPENSSL_BIN!" pkeyutl -verify -pubin -inkey "!PINNED_PUB!" -rawin -in "%UPDATE_ZIP%" -sigfile "%UPDATE_SIG%" >nul 2>&1
if errorlevel 1 (
    echo [安全] 验签失败，更新包可能被篡改或来源不可信，已中止安装。
    del "%UPDATE_ZIP%" 2>nul
    del "%UPDATE_SIG%" 2>nul
    popd
    exit /b 1
)
echo [更新] 签名验证通过。

powershell -NoProfile -Command "Expand-Archive -Path '%UPDATE_ZIP%' -DestinationPath '%UPDATE_DIR%' -Force"

REM 查找更新负载目录
set "PAYLOAD="
if exist "%UPDATE_DIR%\PocketClaw\VERSION" (
    set "PAYLOAD=%UPDATE_DIR%\PocketClaw"
) else (
    for /d %%d in ("%UPDATE_DIR%\*") do (
        if exist "%%d\VERSION" set "PAYLOAD=%%d"
    )
)

if "!PAYLOAD!"=="" (
    echo [错误] 更新包格式异常，请手动更新
    del "%UPDATE_ZIP%" 2>nul
    rmdir /s /q "%UPDATE_DIR%" 2>nul
    popd
    exit /b 1
)

echo [更新] 正在安装更新...

REM 复制根目录文件（不覆盖 .env）
for %%f in ("!PAYLOAD!\*") do (
    if /i not "%%~nxf"==".env" (
        copy /y "%%f" "%PROJECT_DIR%\" >nul 2>&1
    )
)

REM 复制 scripts/
if exist "!PAYLOAD!\scripts" (
    xcopy /e /y /q "!PAYLOAD!\scripts\*" "%PROJECT_DIR%\scripts\" >nul 2>&1
)

REM 复制 config/ 下的文件
if exist "!PAYLOAD!\config" (
    for %%f in ("!PAYLOAD!\config\*") do (
        if "%%~af" neq "d" copy /y "%%f" "%PROJECT_DIR%\config\" >nul 2>&1
    )
)

REM 复制 config/workspace/ 下的 .md 文件
if exist "!PAYLOAD!\config\workspace" (
    for %%f in ("!PAYLOAD!\config\workspace\*.md") do (
        copy /y "%%f" "%PROJECT_DIR%\config\workspace\" >nul 2>&1
    )
)

REM 复制 config/workspace/skills/
if exist "!PAYLOAD!\config\workspace\skills" (
    xcopy /e /y /q "!PAYLOAD!\config\workspace\skills\*" "%PROJECT_DIR%\config\workspace\skills\" >nul 2>&1
)

REM 清除构建哈希，强制重新构建新版本的镜像
del "%PROJECT_DIR%\data\.build_hash" 2>nul

set /p NEW_VER=<"!PAYLOAD!\VERSION"

echo.
echo ============================================
echo   [OK] 更新完成! v!NEW_VER!
echo        下次启动时将使用新版本
echo ============================================
echo.

REM 清理临时文件
del "%UPDATE_ZIP%" 2>nul
rmdir /s /q "%UPDATE_DIR%" 2>nul

popd
exit /b 0
