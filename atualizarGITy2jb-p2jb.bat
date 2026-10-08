@echo off
chcp 65001 >nul
setlocal EnableExtensions

REM ==========================================================
REM  ESPELHO LOCAL -> GITHUB  (REPO + RELEASE / WSL)
REM
REM  LOGICA BASEADA NA REFERENCIA FUNCIONAL:
REM  - Janela principal apenas coordena.
REM  - Cada etapa roda em janela separada.
REM  - Controle somente por errorlevel.
REM  - Sem staging temporario.
REM  - Sem STEP.ok.
REM  - Sem gh api.
REM  - Sem script WSL temporario.
REM  - Release via: gh release view / upload --clobber / create.
REM ==========================================================

if /i "%~1"=="__STEP1__" goto STEP1
if /i "%~1"=="__STEP2__" goto STEP2

if /i "%~1" NEQ "__RUN__" (
  start "Y2JB-P2JB - ESPELHO GITHUB" /max "%ComSpec%" /k ""%~f0" __RUN__"
  exit /b
)

call :SETVARS
if errorlevel 1 (
  echo.
  echo [ERRO] Falha ao detectar variaveis/requisitos.
  echo.
  pause
  exit /b 1
)

cls
echo ==========================================================
echo  ESPELHO LOCAL -^> GITHUB  ^(REPO + RELEASE / WSL^)
echo ==========================================================
echo.
echo Local Windows : %WIN_SRC%
echo Local WSL     : %WSL_SRC%
echo Repositorio   : %REPO%
echo Branch        : %BRANCH%
echo Release       : %TAG%
echo.
echo ----------------------------------------------------------
echo  LOGICA FIXA
echo ----------------------------------------------------------
echo  - C:\GitHub\y2jb-p2jb e a fonte da verdade.
echo  - Arquivos normais vao para o repositorio Git.
echo  - Arquivos .elf, .zip e .exe vao para a GitHub Release via WSL/gh.
echo  - Janela principal apenas coordena, como na referencia.
echo  - Se qualquer etapa falhar, nada e tratado como concluido.
echo ----------------------------------------------------------
echo.

echo -----------------------------------------------
echo [1/2] Espelhar repositorio Git
echo -----------------------------------------------
echo.
echo [INFO] Abrindo janela da etapa 1/2...
start "1- Espelhar Repo Git" /wait "%ComSpec%" /c ""%~f0" __STEP1__"
if errorlevel 1 (
  echo.
  echo [ERRO] Falha ao espelhar o repositorio Git.
  echo.
  pause
  exit /b 1
)
echo [OK] Repositorio Git atualizado.
echo.

echo -----------------------------------------------
echo [2/2] Atualizar Release (.elf + .zip + .exe)
echo -----------------------------------------------
echo.
echo [INFO] Repo: %REPO%
echo [INFO] Tag : %TAG%
echo [INFO] Assets:
echo   %WIN_SRC%\*.elf
echo   %WIN_SRC%\*.zip
echo   %WIN_SRC%\*.exe
echo.
echo [INFO] Abrindo janela da etapa 2/2...
start "2- Atualizar Release (WSL)" /wait "%ComSpec%" /c ""%~f0" __STEP2__"
if errorlevel 1 (
  echo.
  echo [ERRO] Falha ao atualizar a Release.
  echo.
  pause
  exit /b 1
)

echo.
echo ==========================================================
echo [OK] Concluido.
echo ==========================================================
echo.
pause
exit

REM ==========================================================
REM  STEP1 - GIT
REM  Espelha arquivos normais.
REM  .elf, .zip e .exe ficam fora do Git.
REM ==========================================================
:STEP1
title 1- Espelhar Repo Git
cls
call :SETVARS
if errorlevel 1 exit /b 1

echo ==========================================================
echo  [STEP1] ESPELHAR REPOSITORIO GIT
echo ==========================================================
echo.
echo [INFO] Local       : %WIN_SRC%
echo [INFO] Remoto      : %REMOTE_URL%
echo [INFO] Branch      : %BRANCH%
echo [INFO] Fora do Git : *.elf, *.zip e *.exe
echo.

cd /d "%WIN_SRC%"
if errorlevel 1 (
  echo.
  echo [ERRO] Falha ao entrar na pasta local.
  echo.
  pause
  exit /b 1
)

"%GIT_EXE%" init
if errorlevel 1 (
  echo.
  echo [ERRO] Falha no git init.
  echo.
  pause
  exit /b 1
)

"%GIT_EXE%" remote remove origin >nul 2>&1
"%GIT_EXE%" remote add origin "%REMOTE_URL%"
if errorlevel 1 (
  echo.
  echo [ERRO] Falha ao configurar origin.
  echo.
  pause
  exit /b 1
)

echo [INFO] Criando branch limpa para o espelho...
"%GIT_EXE%" checkout --orphan __mirror_tmp__ >nul 2>&1
if errorlevel 1 (
  "%GIT_EXE%" checkout -B __mirror_tmp__
  if errorlevel 1 (
    echo.
    echo [ERRO] Falha ao preparar branch de espelho.
    echo.
    pause
    exit /b 1
  )
)

"%GIT_EXE%" rm -rf --cached . >nul 2>&1

echo [INFO] Adicionando arquivos normais...
"%GIT_EXE%" add -A -f -- . ":(exclude)*.elf" ":(exclude)*.zip" ":(exclude)*.exe"
if errorlevel 1 (
  echo.
  echo [ERRO] Falha no git add.
  echo.
  pause
  exit /b 1
)

echo.
echo [INFO] Status do Git:
"%GIT_EXE%" status --short
echo.

"%GIT_EXE%" commit --allow-empty -m "Espelhar arquivos locais normais"
if errorlevel 1 (
  echo.
  echo [ERRO] Falha no git commit.
  echo.
  pause
  exit /b 1
)

"%GIT_EXE%" branch -D "%BRANCH%" >nul 2>&1
"%GIT_EXE%" branch -m "%BRANCH%"
if errorlevel 1 (
  echo.
  echo [ERRO] Falha ao definir branch %BRANCH%.
  echo.
  pause
  exit /b 1
)

"%GIT_EXE%" push -u origin "%BRANCH%" --force
if errorlevel 1 (
  echo.
  echo [ERRO] Falha no push do repositorio Git.
  echo.
  pause
  exit /b 1
)

echo.
echo [OK] STEP1 concluida.
timeout /t 2 >nul
exit /b 0

REM ==========================================================
REM  STEP2 - RELEASE VIA WSL/GH
REM  MESMA LOGICA DA REFERENCIA:
REM  - monta lista de assets no Windows
REM  - chama gh dentro do WSL
REM  - se release existe: gh release upload --clobber
REM  - se release nao existe: gh release create
REM ==========================================================
:STEP2
title 2- Atualizar Release (WSL)
cls
call :SETVARS
if errorlevel 1 exit /b 1

setlocal EnableExtensions EnableDelayedExpansion
set "ASSET_ARGS="
set "ASSET_COUNT=0"

for %%F in ("%WIN_SRC%\*.elf" "%WIN_SRC%\*.zip" "%WIN_SRC%\*.exe") do (
  if exist "%%~fF" (
    set /a ASSET_COUNT+=1
    set "ASSET_ARGS=!ASSET_ARGS! '%WSL_SRC%/%%~nxF'"
  )
)

if "!ASSET_COUNT!"=="0" (
  endlocal
  echo.
  echo [ERRO] Nenhum .elf, .zip ou .exe encontrado em %WIN_SRC%
  echo.
  pause
  exit /b 1
)

set "ASSET_ARGS_OUT=%ASSET_ARGS%"
set "ASSET_COUNT_OUT=%ASSET_COUNT%"
endlocal & (
  set "ASSET_ARGS=%ASSET_ARGS_OUT%"
  set "ASSET_COUNT=%ASSET_COUNT_OUT%"
)

echo ==========================================================
echo  [STEP2] ATUALIZAR RELEASE ^(GITHUB^) - WSL
echo ==========================================================
echo.
echo [INFO] Repo     : %REPO%
echo [INFO] Tag      : %TAG%
echo [INFO] Assets   : %WSL_SRC%/*.elf, %WSL_SRC%/*.zip e %WSL_SRC%/*.exe
echo [INFO] QTD      : %ASSET_COUNT%
echo.

where wsl >nul 2>&1
if errorlevel 1 (
  echo.
  echo [ERRO] wsl.exe nao encontrado no Windows.
  echo.
  pause
  exit /b 1
)

wsl bash -lc "set -e; echo '[INFO] REPO esperado: %REPO%'; echo '[INFO] TAG esperada: %TAG%'; echo '[INFO] Envio 1:1 dos assets locais com clobber'; command -v gh >/dev/null 2>&1 || { echo '[ERRO] gh nao encontrado no WSL'; exit 1; }; gh auth status -h github.com >/dev/null 2>&1 || { echo '[ERRO] gh nao autenticado no WSL. Rode: gh auth login'; exit 1; }; if gh release view '%TAG%' -R '%REPO%' >/dev/null 2>&1; then echo '[INFO] Release existe. Atualizando assets com clobber...'; gh release upload '%TAG%'%ASSET_ARGS% -R '%REPO%' --clobber; else echo '[INFO] Release nao existe. Criando com assets locais...'; gh release create '%TAG%'%ASSET_ARGS% -R '%REPO%' --title '%TAG%' --notes 'Arquivos desta versao' --latest; fi"

if errorlevel 1 (
  echo.
  echo [ERRO] Falha ao atualizar a Release.
  echo.
  pause
  exit /b 1
)

echo.
echo [OK] Release atualizada.
timeout /t 2 >nul
exit /b 0

REM ==========================================================
REM  VARIAVEIS
REM ==========================================================
:SETVARS
set "WIN_SRC=C:\GitHub\y2jb-p2jb"
set "WSL_SRC=/mnt/c/GitHub/y2jb-p2jb"
set "REPO=ps4macedo/y2jb-p2jb"
set "REMOTE_URL=https://github.com/ps4macedo/y2jb-p2jb.git"
set "BRANCH=main"
set "TAG=1.0"

if not exist "%WIN_SRC%" exit /b 1

set "GIT_EXE="
if exist "%ProgramFiles%\Git\cmd\git.exe" set "GIT_EXE=%ProgramFiles%\Git\cmd\git.exe"
if not defined GIT_EXE if exist "%ProgramFiles%\Git\bin\git.exe" set "GIT_EXE=%ProgramFiles%\Git\bin\git.exe"
if not defined GIT_EXE if exist "%ProgramFiles(x86)%\Git\cmd\git.exe" set "GIT_EXE=%ProgramFiles(x86)%\Git\cmd\git.exe"
if not defined GIT_EXE for /f "delims=" %%G in ('where git 2^>nul') do if not defined GIT_EXE set "GIT_EXE=%%G"
if not defined GIT_EXE exit /b 1

exit /b 0
