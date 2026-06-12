@echo off
setlocal EnableDelayedExpansion
REM ============================================================
REM encrypt.bat  —— 加密 .env 文件 (AES-256-CBC)  [Windows]
REM 用法: scripts\encrypt.bat
REM ============================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "PROJECT_DIR=%CD%"

set "ENV_FILE=%PROJECT_DIR%\.env"
set "ENC_FILE=%PROJECT_DIR%\secrets\.env.encrypted"
set "SECRETS_DIR=%PROJECT_DIR%\secrets"

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

REM --------------- 检查 .env ---------------
if not exist "%ENV_FILE%" (
    echo [错误] 未找到 .env 文件: %ENV_FILE%
    echo 请先运行 setup-env.bat 创建 .env, 或从 .env.example 复制.
    popd
    pause
    exit /b 1
)

REM --------------- 输入密码 ---------------
echo.
echo === PocketClaw .env 加密工具 ===
echo   密码要求: 两次输入一致即可（任意长度）
echo.

:ask_encrypt_pass
REM 使用 PowerShell 读取密码（输入时显示 * 号遮蔽）
for /f "delims=" %%p in ('powershell -NoProfile -Command "$p = Read-Host -Prompt '  请输入加密密码' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "MASTER_PASS=%%p"

if "!MASTER_PASS!"=="" (
    echo [错误] 密码不能为空.
    echo.
    goto :ask_encrypt_pass
)

REM 确认密码也使用 PowerShell 掩码输入
for /f "delims=" %%p in ('powershell -NoProfile -Command "$p = Read-Host -Prompt '  请再次确认密码' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "MASTER_PASS2=%%p"

if not "!MASTER_PASS!"=="!MASTER_PASS2!" (
    echo [错误] 两次密码不一致, 请重新输入.
    echo.
    goto :ask_encrypt_pass
)

REM --------------- 创建 secrets 目录 ---------------
if not exist "%SECRETS_DIR%" mkdir "%SECRETS_DIR%"

REM --------------- 执行加密 ---------------
echo.
echo [信息] 正在加密 .env ...

REM 通过 stdin 传递密码，避免进程列表泄露
<nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 ^
    -in "%ENV_FILE%" ^
    -out "%ENC_FILE%" ^
    -pass stdin

if errorlevel 1 (
    echo [错误] 加密失败, 请检查 OpenSSL 版本.
    popd
    pause
    exit /b 1
)

REM 验证: 用同一密码试解密, 确保密文正确
REM PBKDF2 跨平台兼容：先试 600000 迭代，失败再回退 100000（兼容旧 Windows 密文）
<nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 600000 -in "%ENC_FILE%" -pass stdin || <nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "%ENC_FILE%" -pass stdin > nul 2>&1
if errorlevel 1 (
    echo [错误] 加密验证失败! 密文可能损坏, 请重试.
    del /q "%ENC_FILE%" 2>nul
    popd
    pause
    exit /b 1
)

echo [OK] 加密成功! (已验证密文完整性)
echo   加密文件: %ENC_FILE%
echo.
echo [建议] 加密完成后, 可以删除明文 .env 文件:
echo   del "%ENV_FILE%"
echo.
echo [重要] 请牢记 Master Password, 丢失将无法恢复!

popd
pause
exit /b 0

