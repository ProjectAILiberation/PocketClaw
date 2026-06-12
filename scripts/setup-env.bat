@echo off
setlocal EnableDelayedExpansion
REM ============================================================
REM setup-env.bat  —— 首次配置向导, 生成 .env 文件 [Windows]
REM 用法: scripts\setup-env.bat
REM ============================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "PROJECT_DIR=%CD%"

set "ENV_FILE=%PROJECT_DIR%\.env"

REM --------------- 检查 .env ---------------
if exist "%ENV_FILE%" (
    echo [警告] .env 文件已存在.
    set /p "CONFIRM=是否覆盖? (y/N): "
    if /i not "!CONFIRM!"=="y" (
        echo 已取消.
        popd
        pause
        exit /b 0
    )
)

echo.
echo ===================================================
echo       PocketClaw 首次配置向导
echo       只需 3 步即可完成！
echo ===================================================
echo.
REM ==========================================
REM 1. 选择 AI 模型提供商
REM ==========================================
echo -- [第 1 步] 选择 AI 模型提供商 --
echo.
echo   [1] 免费模型（推荐，无需付费）
echo       智谱 GLM / iFlow 心流，注册即用
echo.
echo   [2] 付费模型（需自备 API Key）
echo       支持 OpenAI / Gemini / Claude / Grok / DeepSeek 等
echo.
:ask_provider
set "PROVIDER_CHOICE="
set /p "PROVIDER_CHOICE=请选择 [1-2]: "
if "!PROVIDER_CHOICE!"=="1" goto :free_models
if "!PROVIDER_CHOICE!"=="2" goto :other_provider
echo   [错误] 请输入 1 或 2
goto :ask_provider

:free_models
echo.
echo   选择免费 AI 模型:
echo.
echo    [1] iFlow 心流（推荐，多模型聚合）
echo        DeepSeek V3.2 / Qwen3 / Kimi K2 等顶级模型，均免费
echo        注册: https://platform.iflow.cn
echo.
echo    [2] 智谱 GLM-4.7-Flash
echo        200K 上下文，稳定快速，永久免费
echo        注册: https://open.bigmodel.cn
echo.
:ask_free
set "FREE_CHOICE="
set /p "FREE_CHOICE=  请选择 [1-2]: "
if "!FREE_CHOICE!"=="1" goto :iflow_free
if "!FREE_CHOICE!"=="2" goto :zhipu_free
echo   [错误] 请输入 1 或 2
goto :ask_free

:zhipu_free
set "PROV=zhipu"
set "PROV_NAME=智谱 AI"
set "DEFAULT_MODEL=glm-4.7-flash"
set "KEY_URL=https://open.bigmodel.cn/usercenter/apikeys"
goto :ask_apikey

:iflow_free
set "PROV=iflow"
set "PROV_NAME=iFlow 心流"
set "DEFAULT_MODEL=deepseek-v3.2"
set "KEY_URL=https://platform.iflow.cn"
goto :ask_apikey

:other_provider
echo.
echo   选择 AI 提供商:
echo.
echo    [1] 智谱 AI (付费高级)    GLM-4-Plus / GLM-4-Long
echo    [2] DeepSeek              DeepSeek-V3 / R1
echo    [3] OpenAI                GPT-4o / GPT-4.1 / o3-mini
echo    [4] Anthropic Claude      Claude Sonnet 4 / Opus 4
echo    [5] Google Gemini         Gemini 2.5 Flash / Pro
echo    [6] xAI Grok              Grok 3 / Grok 3 Mini
echo    [7] Moonshot/Kimi         长文本能力强
echo    [8] 通义千问 Qwen          阿里云
echo    [9] 零一万物 Yi            Yi-Lightning / Yi-Large
echo   [10] 硅基流动              免费开源模型聚合
echo.
:ask_sub
set "SUB_CHOICE="
set /p "SUB_CHOICE=  请选择 [1-10]: "
if "!SUB_CHOICE!"=="" goto :ask_sub

if "!SUB_CHOICE!"=="1" (
    set "PROV=zhipu-pro"
    set "PROV_NAME=智谱 AI (付费高级)"
    set "DEFAULT_MODEL=glm-4-plus"
    set "KEY_URL=https://open.bigmodel.cn/usercenter/apikeys"
)
if "!SUB_CHOICE!"=="2" (
    set "PROV=deepseek"
    set "PROV_NAME=DeepSeek"
    set "DEFAULT_MODEL=deepseek-chat"
    set "KEY_URL=https://platform.deepseek.com/api_keys"
)
if "!SUB_CHOICE!"=="3" (
    set "PROV=openai"
    set "PROV_NAME=OpenAI"
    set "DEFAULT_MODEL=gpt-4o"
    set "KEY_URL=https://platform.openai.com/api-keys"
)
if "!SUB_CHOICE!"=="4" (
    set "PROV=anthropic"
    set "PROV_NAME=Anthropic Claude"
    set "DEFAULT_MODEL=claude-sonnet-4-20250514"
    set "KEY_URL=https://console.anthropic.com/settings/keys"
)
if "!SUB_CHOICE!"=="5" (
    set "PROV=gemini"
    set "PROV_NAME=Google Gemini"
    set "DEFAULT_MODEL=gemini-2.5-flash"
    set "KEY_URL=https://aistudio.google.com/apikey"
)
if "!SUB_CHOICE!"=="6" (
    set "PROV=xai"
    set "PROV_NAME=xAI Grok"
    set "DEFAULT_MODEL=grok-3-mini"
    set "KEY_URL=https://console.x.ai"
)
if "!SUB_CHOICE!"=="7" (
    set "PROV=moonshot"
    set "PROV_NAME=Moonshot/Kimi"
    set "DEFAULT_MODEL=moonshot-v1-auto"
    set "KEY_URL=https://platform.moonshot.cn/console/api-keys"
)
if "!SUB_CHOICE!"=="8" (
    set "PROV=qwen"
    set "PROV_NAME=通义千问 Qwen"
    set "DEFAULT_MODEL=qwen-turbo-latest"
    set "KEY_URL=https://dashscope.console.aliyun.com/apiKey"
)
if "!SUB_CHOICE!"=="9" (
    set "PROV=yi"
    set "PROV_NAME=零一万物 Yi"
    set "DEFAULT_MODEL=yi-lightning"
    set "KEY_URL=https://platform.lingyiwanwu.com/apikeys"
)
if "!SUB_CHOICE!"=="10" (
    set "PROV=siliconflow"
    set "PROV_NAME=硅基流动 SiliconFlow"
    set "DEFAULT_MODEL=deepseek-ai/DeepSeek-V3"
    set "KEY_URL=https://cloud.siliconflow.cn/account/ak"
)
if not defined PROV (
    echo   [错误] 无效选择，请重新输入。
    goto :ask_sub
)

REM ==========================================
REM 2. 获取 API Key
REM ==========================================
:ask_apikey
echo.
echo -- [第 2 步] 获取 !PROV_NAME! API Key --
echo.
if "!PROV!"=="zhipu" (
    echo   PocketClaw 使用智谱 GLM-4.7-Flash 模型
    echo.
    echo   获取 API Key:
    echo   1. 打开 https://open.bigmodel.cn
    echo   2. 注册/登录, 进入 API密钥 页面
    echo   3. 创建新 API Key, 复制生成的密钥
) else if "!PROV!"=="iflow" (
    echo   PocketClaw 使用 iFlow 心流免费模型聚合
    echo.
    echo   获取 API Key:
    echo   1. 打开 https://platform.iflow.cn
    echo   2. 注册/登录后, 点击「API Key 管理」
    echo   3. 点击「重置 API 密钥」, 复制生成的 Key
    echo.
    echo   [!] 注意: API Key 有效期只有7天
    echo       到期后需再次点击「重置 API 密钥」获取新 Key
    echo       并通过「切换 API」重新输入到 PocketClaw
) else (
    echo   已选择: !PROV_NAME!
    echo   默认模型: !DEFAULT_MODEL!
    echo.
    echo   获取 API Key: !KEY_URL!
)
echo.
:ask_key_input
set "API_KEY="
set /p "API_KEY=  请粘贴你的 API Key: "
if "!API_KEY!"=="" (
    echo   [错误] API Key 不能为空。
    goto :ask_key_input
)

echo   [OK] API Key 已录入
echo.
REM ==========================================
REM 生成 .env 文件
REM ==========================================
(
echo # PocketClaw 环境配置文件
echo # 由首次配置向导自动生成
echo.
echo COMPOSE_PROJECT_NAME=pocketclaw
echo.
echo PROVIDER_NAME=!PROV!
echo.
echo OPENCLAW_MODEL=!DEFAULT_MODEL!
echo.
echo OPENAI_API_KEY=!API_KEY!
echo.
echo GATEWAY_AUTH_PASSWORD=pocketclaw
echo.
) > "%ENV_FILE%"

echo.
echo ===================================================
echo            [OK] API Key 配置完成！
echo ===================================================
echo.

REM ==========================================
REM 3. 设置 Master Password
REM ==========================================
echo -- [第 3 步] 设置 Master Password（保护你的密钥）--
echo.
echo   Master Password 用于加密你的 API Key。
echo   每次启动 PocketClaw 时需要输入此密码。
echo   如果忘记密码，需要重新配置 API Key。
echo.
:ask_password
for /f "delims=" %%p in ('powershell -NoProfile -Command "$p = Read-Host -Prompt '  请输入 Master Password' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "MASTER_PASS=%%p"
if "!MASTER_PASS!"=="" (
    echo   [错误] 密码不能为空。
    goto ask_password
)

:ask_password2
for /f "delims=" %%p in ('powershell -NoProfile -Command "$p = Read-Host -Prompt '  请再次确认密码' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "MASTER_PASS2=%%p"
if not "!MASTER_PASS!"=="!MASTER_PASS2!" (
    echo   [错误] 两次密码不一致，请重新设置。
    goto ask_password
)

echo.
echo [信息] 正在加密配置文件...

REM 确保 openssl 可用
where openssl >nul 2>&1
if !ERRORLEVEL! neq 0 (
    if exist "C:\Program Files\Git\usr\bin\openssl.exe" (
        set "PATH=C:\Program Files\Git\usr\bin;%PATH%"
    )
)

set "SECRETS_DIR=%PROJECT_DIR%\secrets"
if not exist "%SECRETS_DIR%" mkdir "%SECRETS_DIR%"
set "ENC_FILE=%SECRETS_DIR%\.env.encrypted"

<nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 ^
    -in "%ENV_FILE%" ^
    -out "!ENC_FILE!" ^
    -pass stdin 2>nul

if !ERRORLEVEL! neq 0 (
    echo [错误] 加密失败，配置文件仍为明文保存。
    echo        请稍后运行 scripts\encrypt.bat 手动加密。
) else (
    echo [OK] 配置已加密保护！
    echo [信息] 加密备份已保存到 secrets\.env.encrypted
    REM 安全擦除明文.env
    powershell -NoProfile -Command "$f='!ENV_FILE!'; if(Test-Path $f){$s=(Get-Item $f).Length; $r=New-Object byte[] $s; [Security.Cryptography.RandomNumberGenerator]::Fill($r); [IO.File]::WriteAllBytes($f,$r)}" 2>nul
    del /q "!ENV_FILE!" 2>nul
    echo        明文 .env 已安全擦除。
)

echo.
echo ===================================================
echo            全部配置完成！
echo ===================================================
echo.
echo   提示: 除了浏览器 WebChat，你还可以接入
echo   Telegram / Discord / Slack / WhatsApp 等
echo   10 种聊天软件来与 AI 对话！
echo.
echo   配置方法: 运行 scripts\setup-channels.bat
echo.
echo   启动脚本将自动启动 PocketClaw。
echo.

popd
exit /b 0

