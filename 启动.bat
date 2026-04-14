@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

set "MODEL=qwen3-merged-aigc_zhv3-Q4_K_M.gguf"
set "MODEL_URL_MIRROR=https://hf-mirror.com/skskk/aigc-rewriter/resolve/main/qwen3-merged-aigc_zhv3-Q4_K_M.gguf"
set "MODEL_URL_FALLBACK=https://huggingface.co/skskk/aigc-rewriter/resolve/main/qwen3-merged-aigc_zhv3-Q4_K_M.gguf?download=true"
set "LLAMA_SERVER="
set "PREFERRED_DIR=llama-b8721-bin-win-vulkan-x64"
set "AUTO_ZIP=llama-b8783-bin-win-vulkan-x64.zip"
set "AUTO_URL_MIRROR=https://gh-proxy.com/https://github.com/ggml-org/llama.cpp/releases/download/b8783/llama-b8783-bin-win-vulkan-x64.zip"
set "AUTO_URL_FALLBACK=https://github.com/ggml-org/llama.cpp/releases/download/b8783/llama-b8783-bin-win-vulkan-x64.zip"
set "AUTO_TMP=__llama_auto_tmp"

if not exist "%MODEL%" (
  echo [WARN] Missing model: %MODEL%
  echo [INFO] Trying auto download from Hugging Face...
  call :auto_download_model
)

if not exist "%MODEL%" (
  echo [ERROR] Model still missing after auto download: %MODEL%
  pause
  exit /b 1
)

call :scan_llama_server
if not defined LLAMA_SERVER (
  echo [WARN] llama-server.exe not found, trying auto download and extract...
  call :auto_install_llama
)

if not defined LLAMA_SERVER (
  echo [ERROR] llama-server.exe not found under: %~dp0
  echo [HINT] Auto install failed. Please manually place llama-server.exe under this repo.
  pause
  exit /b 1
)

echo [INFO] Found llama-server.exe: %LLAMA_SERVER%
echo [INFO] Starting llama-server on http://127.0.0.1:8181 ...
start http://127.0.0.1:8181
"%LLAMA_SERVER%" ^
  -m "%MODEL%" ^
  --host 127.0.0.1 ^
  --port 8181 ^
  --path . ^
  --reasoning off ^
  --reasoning-format none

endlocal
exit /b 0

:scan_llama_server
set "LLAMA_SERVER="

rem 1) preferred known location
if exist "%~dp0%PREFERRED_DIR%\llama-server.exe" (
  set "LLAMA_SERVER=%~dp0%PREFERRED_DIR%\llama-server.exe"
  goto :eof
)

rem 2) first-level folders in repo root
for /d %%D in ("%~dp0*") do (
  if exist "%%~fD\llama-server.exe" (
    set "LLAMA_SERVER=%%~fD\llama-server.exe"
    goto :eof
  )
)

rem 3) recursive fallback scan
for /r "%~dp0" %%F in (llama-server.exe) do (
  if exist "%%~fF" (
    set "LLAMA_SERVER=%%~fF"
    goto :eof
  )
)

goto :eof

:auto_download_model
set "MODEL_PATH=%~dp0%MODEL%"
set "MODEL_TMP_PATH=%MODEL_PATH%.part"
set "PART_SIZE=0"

if exist "%MODEL_TMP_PATH%" (
  for %%I in ("%MODEL_TMP_PATH%") do set "PART_SIZE=%%~zI"
  if !PART_SIZE! LSS 1048576 (
    echo [INFO] Existing partial file is too small, restarting download...
    del /f /q "%MODEL_TMP_PATH%" >nul 2>nul
  )
)

echo [INFO] Downloading model (mirror): %MODEL_URL_MIRROR%

call :download_file "%MODEL_URL_MIRROR%" "%MODEL_TMP_PATH%"
if errorlevel 1 (
  echo [WARN] Mirror download failed, trying official source...
  call :download_file "%MODEL_URL_FALLBACK%" "%MODEL_TMP_PATH%"
)

if errorlevel 1 (
  echo [ERROR] Failed to download model from both mirror and official source.
  goto :eof
)

if not exist "%MODEL_TMP_PATH%" (
  echo [ERROR] Downloaded model temp file not found: %MODEL_TMP_PATH%
  goto :eof
)

for %%I in ("%MODEL_TMP_PATH%") do set "MODEL_SIZE=%%~zI"
if !MODEL_SIZE! LSS 1048576 (
  echo [ERROR] Downloaded model file is too small: !MODEL_SIZE! bytes
  del /f /q "%MODEL_TMP_PATH%" >nul 2>nul
  goto :eof
)

move /y "%MODEL_TMP_PATH%" "%MODEL_PATH%" >nul
if errorlevel 1 (
  echo [ERROR] Failed to finalize model file: %MODEL_PATH%
  goto :eof
)

echo [INFO] Model download completed: %MODEL%
goto :eof

:download_file
set "DL_URL=%~1"
set "DL_OUT=%~2"

where curl.exe >nul 2>nul
if %errorlevel% EQU 0 (
  echo [INFO] Download method: curl.exe ^(resume enabled^)
  set /a CURL_TRY=1
  for /l %%N in (1,1,12) do (
    curl.exe -L -C - --retry 0 --connect-timeout 20 -o "%DL_OUT%" "%DL_URL%"
    if !errorlevel! EQU 0 goto :eof
    if %%N LSS 12 (
      echo [WARN] curl interrupted, resume retry %%N/12 in 2s...
      ping -n 3 127.0.0.1 >nul 2>nul
    )
  )
  echo [WARN] curl resume failed, trying BITS...
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$url=$env:DL_URL;" ^
  "$out=$env:DL_OUT;" ^
  "Start-BitsTransfer -Source $url -Destination $out -RetryInterval 5 -RetryTimeout 300"

if %errorlevel% EQU 0 goto :eof
echo [WARN] BITS failed, trying Invoke-WebRequest retry loop...

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$ProgressPreference='SilentlyContinue';" ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
  "$url=$env:DL_URL;" ^
  "$out=$env:DL_OUT;" ^
  "for ($i = 1; $i -le 5; $i++) {" ^
  "  try { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing; exit 0 }" ^
  "  catch {" ^
  "    if ($i -eq 5) { throw }" ^
  "    Start-Sleep -Seconds ([Math]::Min(5 * $i, 20))" ^
  "  }" ^
  "}"

if %errorlevel% EQU 0 goto :eof
exit /b 1

goto :eof

:auto_install_llama
set "ZIP_PATH=%~dp0%AUTO_ZIP%"
set "TMP_PATH=%~dp0%AUTO_TMP%"
set "DEST_PATH=%~dp0%PREFERRED_DIR%"
echo [INFO] Downloading llama.cpp package (mirror): %AUTO_URL_MIRROR%

if exist "%ZIP_PATH%" del /f /q "%ZIP_PATH%" >nul 2>nul
call :download_file "%AUTO_URL_MIRROR%" "%ZIP_PATH%"
if errorlevel 1 (
  echo [WARN] Mirror download failed, trying official source...
  if exist "%ZIP_PATH%" del /f /q "%ZIP_PATH%" >nul 2>nul
  call :download_file "%AUTO_URL_FALLBACK%" "%ZIP_PATH%"
)

if errorlevel 1 (
  echo [ERROR] Failed to download llama.cpp package from both mirror and official source.
  goto :eof
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$zip='%ZIP_PATH%';" ^
  "$tmp='%TMP_PATH%';" ^
  "$dest='%DEST_PATH%';" ^
  "if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force };" ^
  "New-Item -ItemType Directory -Path $tmp | Out-Null;" ^
  "Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force;" ^
  "$server = Get-ChildItem -Path $tmp -Recurse -Filter 'llama-server.exe' | Select-Object -First 1;" ^
  "if (-not $server) { throw 'llama-server.exe not found in downloaded archive.' };" ^
  "if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null };" ^
  "Copy-Item -Path (Join-Path $server.Directory.FullName '*') -Destination $dest -Recurse -Force"

if errorlevel 1 (
  echo [ERROR] Downloaded package extract failed.
  goto :eof
)

if exist "%ZIP_PATH%" del /f /q "%ZIP_PATH%" >nul 2>nul
if exist "%TMP_PATH%" rmdir /s /q "%TMP_PATH%" >nul 2>nul

if exist "%DEST_PATH%\llama-server.exe" (
  set "LLAMA_SERVER=%DEST_PATH%\llama-server.exe"
) else (
  for /r "%DEST_PATH%" %%F in (llama-server.exe) do (
    if exist "%%~fF" (
      set "LLAMA_SERVER=%%~fF"
      goto :after_set_server
    )
  )
)

:after_set_server
echo [INFO] Auto install completed.
goto :eof
