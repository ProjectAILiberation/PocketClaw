@echo off
setlocal EnableDelayedExpansion
REM ============================================================
REM change-api.bat  —— 切换 AI 模型提供商 / 更新 API Key
REM ============================================================

set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%.."
set "PROJECT_DIR=%CD%"

set "ENV_FILE=%PROJECT_DIR%\.env"
set "ENC_FILE=%PROJECT_DIR%\secrets\.env.encrypted"
set "PROVIDER_FILE=%PROJECT_DIR%\config\workspace\.provider"
set "BOUND_FILE=%PROJECT_DIR%\config\workspace\.bound_providers"
set "NEED_REENCRYPT=0"
set "MASTER_PASS="

REM --------------- 确保 openssl 可用 ---------------
where openssl >nul 2>&1
if errorlevel 1 (
    if exist "C:\Program Files\Git\usr\bin\openssl.exe" (
        set "PATH=C:\Program Files\Git\usr\bin;%PATH%"
    )
)

echo.
echo ===================================================
echo       PocketClaw 模型切换工具
echo ===================================================
echo.
echo   选择 AI 模型提供商:
echo.
echo   [1] iFlow 心流        (推荐，免费多模型聚合)
echo       DeepSeek V3.2 / Qwen3 / Kimi K2 等顶级模型，均免费
echo       注册: https://platform.iflow.cn
echo.
echo   [2] 智谱 AI          (免费)
echo       GLM-4.7-Flash / GLM-4.6V-Flash / GLM-Z1-Flash
echo       注册: https://open.bigmodel.cn
echo.
echo   [3] DeepSeek          (性价比最高)
echo       DeepSeek-V3 / DeepSeek-R1
echo       注册: https://platform.deepseek.com
echo.
echo   [4] Moonshot/Kimi     (长文本能力强)
echo       Moonshot-v1 (8K/32K/128K)
echo       注册: https://platform.moonshot.cn
echo.
echo   [5] 通义千问 Qwen     (阿里云)
echo       Qwen-Turbo / Qwen-Plus / Qwen-Max
echo       注册: https://dashscope.console.aliyun.com
echo.
echo   [6] 零一万物 Yi       (性能优秀)
echo       Yi-Lightning / Yi-Large
echo       注册: https://platform.lingyiwanwu.com
echo.
echo   [7] 硅基流动          (免费开源模型聚合)
echo       DeepSeek V3/R1 / Qwen / GLM (均免费)
echo       注册: https://cloud.siliconflow.cn
echo.
echo   [8] 智谱 AI (付费高级) GLM-4-Plus / GLM-4-Long
echo       注册: https://open.bigmodel.cn
echo.
echo   [9] OpenAI             GPT-4o / GPT-4.1 / o3-mini
echo       注册: https://platform.openai.com
echo.
echo  [10] Anthropic Claude   Claude Sonnet 4 / Opus 4
echo       注册: https://console.anthropic.com
echo.
echo  [11] Google Gemini      Gemini 2.5 Flash / Pro
echo       注册: https://aistudio.google.com
echo.
echo  [12] xAI Grok           Grok 3 / Grok 3 Mini
echo       注册: https://console.x.ai
echo.
echo   [0] 仅更新当前 API Key (不切换提供商)
echo.

:ask_menu
set "MENU_CHOICE="
set /p "MENU_CHOICE=请选择 [0-12]: "
if "!MENU_CHOICE!"=="0" goto :update_key_only

if "!MENU_CHOICE!"=="1" (
    set "PROV=iflow"
    set "PROV_NAME=iFlow 心流"
    set "DEFAULT_MODEL=deepseek-v3.2"
    set "KEY_URL=https://platform.iflow.cn"
)
if "!MENU_CHOICE!"=="2" (
    set "PROV=zhipu"
    set "PROV_NAME=智谱 AI"
    set "DEFAULT_MODEL=glm-4.7-flash"
    set "KEY_URL=https://open.bigmodel.cn/usercenter/apikeys"
)
if "!MENU_CHOICE!"=="3" (
    set "PROV=deepseek"
    set "PROV_NAME=DeepSeek"
    set "DEFAULT_MODEL=deepseek-chat"
    set "KEY_URL=https://platform.deepseek.com/api_keys"
)
if "!MENU_CHOICE!"=="4" (
    set "PROV=moonshot"
    set "PROV_NAME=Moonshot/Kimi"
    set "DEFAULT_MODEL=moonshot-v1-auto"
    set "KEY_URL=https://platform.moonshot.cn/console/api-keys"
)
if "!MENU_CHOICE!"=="5" (
    set "PROV=qwen"
    set "PROV_NAME=通义千问 Qwen"
    set "DEFAULT_MODEL=qwen-turbo-latest"
    set "KEY_URL=https://dashscope.console.aliyun.com/apiKey"
)
if "!MENU_CHOICE!"=="6" (
    set "PROV=yi"
    set "PROV_NAME=零一万物 Yi"
    set "DEFAULT_MODEL=yi-lightning"
    set "KEY_URL=https://platform.lingyiwanwu.com/apikeys"
)
if "!MENU_CHOICE!"=="7" (
    set "PROV=siliconflow"
    set "PROV_NAME=硅基流动 SiliconFlow"
    set "DEFAULT_MODEL=deepseek-ai/DeepSeek-V3"
    set "KEY_URL=https://cloud.siliconflow.cn/account/ak"
)
if "!MENU_CHOICE!"=="8" (
    set "PROV=zhipu-pro"
    set "PROV_NAME=智谱 AI (付费高级)"
    set "DEFAULT_MODEL=glm-4-plus"
    set "KEY_URL=https://open.bigmodel.cn/usercenter/apikeys"
)
if "!MENU_CHOICE!"=="9" (
    set "PROV=openai"
    set "PROV_NAME=OpenAI"
    set "DEFAULT_MODEL=gpt-4o"
    set "KEY_URL=https://platform.openai.com/api-keys"
)
if "!MENU_CHOICE!"=="10" (
    set "PROV=anthropic"
    set "PROV_NAME=Anthropic Claude"
    set "DEFAULT_MODEL=claude-sonnet-4-20250514"
    set "KEY_URL=https://console.anthropic.com/settings/keys"
)
if "!MENU_CHOICE!"=="11" (
    set "PROV=gemini"
    set "PROV_NAME=Google Gemini"
    set "DEFAULT_MODEL=gemini-2.5-flash"
    set "KEY_URL=https://aistudio.google.com/apikey"
)
if "!MENU_CHOICE!"=="12" (
    set "PROV=xai"
    set "PROV_NAME=xAI Grok"
    set "DEFAULT_MODEL=grok-3-mini"
    set "KEY_URL=https://console.x.ai"
)
if not defined PROV (
    echo   [错误] 无效选择
    goto :ask_menu
)

echo.
echo   已选择: !PROV_NAME!
echo   获取 API Key: !KEY_URL!
if "!PROV!"=="iflow" (
    echo.
    echo   获取 API Key 步骤:
    echo   1. 打开 https://platform.iflow.cn
    echo   2. 注册/登录后, 点击「API Key 管理」
    echo   3. 点击「重置 API 密钥」, 复制生成的 Key
    echo.
    echo   [!] 注意: API Key 有效期只有7天
    echo       到期后需再次点击「重置 API 密钥」获取新 Key
    echo       并通过「切换 API」重新输入到 PocketClaw
)
echo.

set "NEW_KEY="
set /p "NEW_KEY=  请粘贴你的 !PROV_NAME! API Key: "
if "!NEW_KEY!"=="" (
    echo   [错误] API Key 不能为空。
    popd
    pause
    exit /b 1
)

echo.
echo [信息] 正在保存配置...

REM 写入 workspace/.provider
(
echo # PocketClaw Provider Config
echo PROVIDER_NAME=!PROV!
echo API_KEY=!NEW_KEY!
echo MODEL_ID=!DEFAULT_MODEL!
) > "!PROVIDER_FILE!"

echo   [OK] 提供商配置已保存

REM 记录已绑定的提供商
findstr /x "!PROV!" "!BOUND_FILE!" >nul 2>&1
if errorlevel 1 (
    echo !PROV!>> "!BOUND_FILE!"
)

REM 同时更新 .env
call :do_update_env
goto :restart_prompt

REM ============================================================
:update_key_only
REM 仅更新 API Key (不切换提供商)
echo.

REM 如果 .env 不存在，先解密
if not exist "%ENV_FILE%" (
    if exist "%ENC_FILE%" (
        echo [信息] 正在解密 .env ...
        for /f "delims=" %%p in ('powershell -NoProfile -Command "$p = Read-Host -Prompt '  Master Password' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "MASTER_PASS=%%p"
        REM PBKDF2 跨平台兼容：先试 600000 迭代，失败再回退 100000（兼容旧 Windows 密文）
<nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 600000 -in "%ENC_FILE%" -out "%ENV_FILE%" -pass stdin 2>nul || <nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "%ENC_FILE%" -out "%ENV_FILE%" -pass stdin 2>nul
        if errorlevel 1 (
            echo [错误] 解密失败。
            popd ^& pause ^& exit /b 1
        )
        set "NEED_REENCRYPT=1"
    ) else (
        echo [错误] 未找到配置文件，请先运行 setup-env.bat
        popd ^& pause ^& exit /b 1
    )
) else (
    set "NEED_REENCRYPT=0"
)

REM 显示当前 Key
for /f "tokens=1,* delims==" %%a in ('findstr /i "OPENAI_API_KEY ZHIPU_API_KEY" "%ENV_FILE%" 2^>nul') do set "CUR_KEY=%%b"
if defined CUR_KEY echo   当前 API Key: !CUR_KEY:~0,8!****
echo.
set /p "NEW_KEY=  新的 API Key (留空保持不变): "
if "!NEW_KEY!"=="" (
    echo   未修改。
    goto :do_cleanup
)

REM 更新 .env 中的 key
powershell -NoProfile -Command "(Get-Content '%ENV_FILE%') -replace '^(OPENAI_API_KEY|ZHIPU_API_KEY)=.*', 'OPENAI_API_KEY=!NEW_KEY!' | Set-Content '%ENV_FILE%'"
echo   [OK] API Key 已更新

REM 同时更新 workspace/.provider
if exist "!PROVIDER_FILE!" (
    powershell -NoProfile -Command "(Get-Content '!PROVIDER_FILE!') -replace '^API_KEY=.*', 'API_KEY=!NEW_KEY!' | Set-Content '!PROVIDER_FILE!'"
    echo   [OK] Provider 配置已同步
)

REM 重新加密
if "!NEED_REENCRYPT!"=="1" (
    echo [信息] 重新加密 .env ...
    <nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 ^
        -in "%ENV_FILE%" -out "%ENC_FILE%" -pass stdin 2>nul
    if errorlevel 1 (
        echo [错误] 重新加密失败。
    ) else (
        echo   [OK] 已重新加密
    )
)
goto :restart_prompt

REM ============================================================
:do_update_env
REM 更新或创建 .env 文件

if not exist "%ENV_FILE%" (
    if exist "%ENC_FILE%" (
        for /f "delims=" %%p in ('powershell -NoProfile -Command "$p = Read-Host -Prompt '  Master Password' -AsSecureString; [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do set "MASTER_PASS=%%p"
        REM PBKDF2 跨平台兼容：先试 600000 迭代，失败再回退 100000（兼容旧 Windows 密文）
<nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 600000 -in "%ENC_FILE%" -out "%ENV_FILE%" -pass stdin 2>nul || <nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -in "%ENC_FILE%" -out "%ENV_FILE%" -pass stdin 2>nul
        set "NEED_REENCRYPT=1"
    )
)

if exist "%ENV_FILE%" (
    powershell -NoProfile -Command "$c = Get-Content '%ENV_FILE%'; $c = $c -replace '^(OPENAI_API_KEY|ZHIPU_API_KEY)=.*', 'OPENAI_API_KEY=!NEW_KEY!'; $c = $c -replace '^PROVIDER_NAME=.*', 'PROVIDER_NAME=!PROV!'; $c = $c -replace '^OPENCLAW_MODEL=.*', 'OPENCLAW_MODEL=!DEFAULT_MODEL!'; $c | Set-Content '%ENV_FILE%'"
) else (
    (
    echo COMPOSE_PROJECT_NAME=pocketclaw
    echo PROVIDER_NAME=!PROV!
    echo OPENCLAW_MODEL=!DEFAULT_MODEL!
    echo OPENAI_API_KEY=!NEW_KEY!
    echo GATEWAY_AUTH_PASSWORD=pocketclaw
    ) > "%ENV_FILE%"
)
echo   [OK] .env 已更新

if "!NEED_REENCRYPT!"=="1" (
    echo [信息] 重新加密 .env ...
    <nul set /p ="!MASTER_PASS!"| openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 ^
        -in "%ENV_FILE%" -out "%ENC_FILE%" -pass stdin 2>nul
    if errorlevel 1 (
        echo [错误] 重新加密失败。
    ) else (
        echo   [OK] 已重新加密
    )
)
exit /b 0

REM ============================================================
:restart_prompt
echo.
set /p "RESTART=是否重启 PocketClaw 使更改生效? (Y/n): "
if /i "!RESTART!"=="n" (
    echo.
    echo [提示] 稍后手动重启: docker compose restart
    goto :do_cleanup
)

echo [信息] 正在重启 PocketClaw...
docker compose restart pocketclaw 2>nul
if !ERRORLEVEL! neq 0 (
    echo [信息] 尝试完全重建...
    docker compose up -d --build 2>nul
)
echo [OK] 重启完成！
echo.
if defined PROV_NAME (
    echo   当前提供商: !PROV_NAME!
    echo   当前模型:   !DEFAULT_MODEL!
)
set "ACTUAL_TOKEN=pocketclaw"
if exist "%PROJECT_DIR%\config\workspace\.gateway_token" (
    set /p ACTUAL_TOKEN=<"%PROJECT_DIR%\config\workspace\.gateway_token"
)
echo   控制面板:   http://127.0.0.1:18789/#token=!ACTUAL_TOKEN!

:do_cleanup
REM 安全擦除临时明文 .env
if "!NEED_REENCRYPT!"=="1" (
    powershell -NoProfile -Command "$f='%ENV_FILE%'; if(Test-Path $f){$s=(Get-Item $f).Length; $r=New-Object byte[] $s; [Security.Cryptography.RandomNumberGenerator]::Fill($r); [IO.File]::WriteAllBytes($f,$r)}" 2>nul
    del "%ENV_FILE%" 2>nul
    echo [安全] 已安全擦除明文 .env
)

echo.
popd
pause
exit /b 0

