@echo off
setlocal EnableDelayedExpansion
REM ============================================================
REM decrypt.bat  —— 解密 .env.encrypted → .env  [Windows]
REM 用法: scripts\decrypt.bat
REM ============================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "PROJECT_DIR=%CD%"

set "ENV_FILE=%PROJECT_DIR%\.env"
set "ENC_FILE=%PROJECT_DIR%\secrets\.env.encrypted"

REM --------------- 检查 openssl ---------------
where openssl >nul 2>&1
if errorlevel 1 (
    REM 尝试 Git 自带的 openssl
    if exist "C:\Program Files\Git\usr\bin\openssl.exe" (
        set "PATH=C:\Program Files\Git\usr\bin;%PATH%"
        goto :openssl_ok
    )
    echo [错误] 未找到 openssl.
    echo   请先安装 Git for Windows（自带 OpenSSL）:
    echo   winget install Git.Git
    echo   安装后重启终端即可.
    popd
    pause
    exit /b 1
)
:openssl_ok

REM --------------- 检查加密文件 ---------------
if not exist "%ENC_FILE%" (
    echo [错误] 未找到加密文件: %ENC_FILE%
    echo 请先运行 encrypt.bat 进行加密.
    popd
    pause
    exit /b 1
)

REM --------------- 输入密码 ---------------
echo.
echo === PocketClaw .env 解密工具 ===
echo.
REM 使用 PowerShell 读取密码（输入时显示 * 号遮蔽）
for /f "delims=" %%p in ('powershell -NoProfile -Command "$p = Read-Host -Prompt '  Master Password' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "MASTER_PASS=%%p"

if "!MASTER_PASS!"=="" (
    echo [错误] 密码不能为空.
    popd
    pause
    exit /b 1
)

REM --------------- 检查是否已有 .env ---------------
if exist "%ENV_FILE%" (
    echo [警告] .env 文件已存在, 解密将覆盖.
    set /p "CONFIRM=是否继续? (y/N): "
    if /i not "!CONFIRM!"=="y" (
        echo 已取消.
        popd
        pause
        exit /b 0
    )
)

REM --------------- 执行解密 ---------------
echo.
echo [信息] 正在解密 ...

REM 通过 stdin 传递密码，避免进程列表泄露
REM PBKDF2 跨平台兼容：先试 600000 迭代，失败再回退 100000（兼容旧 Windows 密文）
<nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 600000 -in "%ENC_FILE%" -out "%ENV_FILE%" -pass stdin || <nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "%ENC_FILE%" -out "%ENV_FILE%" -pass stdin

if errorlevel 1 (
    echo [错误] 解密失败, 密码可能不正确.
    if exist "%ENV_FILE%" del "%ENV_FILE%"
    popd
    pause
    exit /b 1
)

echo [OK] 解密成功!
echo   .env 文件已还原: %ENV_FILE%
echo.
echo [安全提示] 使用完毕后, 建议删除明文 .env:
echo   del "%ENV_FILE%"

popd
REM 如果是从其他脚本 call 的则不暂停
if "%~1"=="--no-pause" exit /b 0
pause
exit /b 0

