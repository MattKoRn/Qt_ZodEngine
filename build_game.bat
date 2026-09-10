@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
cd /d "%ROOT%" || exit /b 1

rem Project-local bootstrap settings. The Qt SDK itself is installed per-user so
rem cloning the repository again does not download a second multi-GB toolchain.
set "QZOD_QT_ROOT=%LOCALAPPDATA%\Qt_ZodEngine\Qt"
set "QZOD_QMAKE=%QZOD_QT_ROOT%\5.15.2\mingw81_64\bin\qmake.exe"
set "QZOD_MINGW_BIN=%QZOD_QT_ROOT%\Tools\mingw810_64\bin"
set "QZOD_AQT_DIR=%LOCALAPPDATA%\Qt_ZodEngine\bootstrap"
set "QZOD_AQT_EXE=%QZOD_AQT_DIR%\aqt_x64.exe"
set "QZOD_AQT_URL=https://github.com/miurahr/aqtinstall/releases/download/v3.3.0/aqt_x64.exe"
set "QZOD_AQT_SHA256=4f74d4c95c464d238d7e17ec2d9b7f22a7c333f0f5270a62584e2b47fc765150"

echo [1/3] Checking Qt qmake...

rem Respect an explicitly configured qmake first.
if defined QMAKE_EXE (
    "%QMAKE_EXE%" -v >nul 2>&1
    if not errorlevel 1 goto qmake_found
    echo WARNING: QMAKE_EXE is set but could not be run:
    echo   %QMAKE_EXE%
    set "QMAKE_EXE="
)

rem Then try PATH.
for /f "delims=" %%Q in ('where qmake.exe 2^>nul') do if not defined QMAKE_EXE set "QMAKE_EXE=%%Q"
if defined QMAKE_EXE goto validate_qmake

rem Search common Qt install roots, including this project's automatic SDK.
for %%R in ("C:\Qt" "%USERPROFILE%\Qt" "%LOCALAPPDATA%\Qt" "%QZOD_QT_ROOT%") do (
    if exist "%%~R" (
        for /f "delims=" %%Q in ('dir /b /s "%%~R\qmake.exe" 2^>nul') do if not defined QMAKE_EXE set "QMAKE_EXE=%%Q"
    )
)
if defined QMAKE_EXE goto validate_qmake

rem No qmake exists where expected: bootstrap the known-compatible SDK.
if /I "%QZOD_AUTO_INSTALL_QT%"=="0" goto qmake_missing
goto bootstrap_qt

:validate_qmake
if not defined QMAKE_EXE goto qmake_missing
"%QMAKE_EXE%" -v >nul 2>&1
if errorlevel 1 goto qmake_missing

:qmake_found
echo Using qmake:
echo   %QMAKE_EXE%
for %%Q in ("%QMAKE_EXE%") do set "QT_BIN_DIR=%%~dpQ"
set "PATH=%QT_BIN_DIR%;%PATH%"

set "BUILD_DIR=%ROOT%build-windows"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if errorlevel 1 (
    echo ERROR: Could not create "%BUILD_DIR%".
    exit /b 1
)

pushd "%BUILD_DIR%"
if errorlevel 1 exit /b 1

echo [2/3] Generating Makefiles...
"%QMAKE_EXE%" "%ROOT%Q_ZodEngine.pro"
if errorlevel 1 (
    echo ERROR: qmake failed.
    popd
    exit /b 1
)

set "QMAKE_SPEC="
set "SPEC_FILE=%TEMP%\qzod_qmake_spec_%RANDOM%_%RANDOM%.txt"
"%QMAKE_EXE%" -query QMAKE_XSPEC > "%SPEC_FILE%" 2>nul
set /p "QMAKE_SPEC="<"%SPEC_FILE%"
if not defined QMAKE_SPEC (
    "%QMAKE_EXE%" -query QMAKE_SPEC > "%SPEC_FILE%" 2>nul
    set /p "QMAKE_SPEC="<"%SPEC_FILE%"
)
del "%SPEC_FILE%" >nul 2>&1

if not defined NUMBER_OF_PROCESSORS set "NUMBER_OF_PROCESSORS=2"
set "MAKE_EXE="
set "MAKE_ARGS="

echo %QMAKE_SPEC% | findstr /I "msvc" >nul
if not errorlevel 1 goto choose_msvc_make

rem Prefer a MinGW make already on PATH.
for /f "delims=" %%M in ('where mingw32-make.exe 2^>nul') do if not defined MAKE_EXE set "MAKE_EXE=%%M"
if defined MAKE_EXE (
    set "MAKE_ARGS=-j%NUMBER_OF_PROCESSORS%"
    goto prepare_mingw
)

rem Qt's online installer normally keeps MinGW under its Tools directory.
for %%R in ("C:\Qt\Tools" "%USERPROFILE%\Qt\Tools" "%LOCALAPPDATA%\Qt\Tools" "%QZOD_QT_ROOT%\Tools") do (
    if exist "%%~R" (
        for /f "delims=" %%M in ('dir /b /s "%%~R\mingw32-make.exe" 2^>nul') do if not defined MAKE_EXE set "MAKE_EXE=%%M"
    )
)
if defined MAKE_EXE (
    set "MAKE_ARGS=-j%NUMBER_OF_PROCESSORS%"
    goto prepare_mingw
)

for /f "delims=" %%M in ('where make.exe 2^>nul') do if not defined MAKE_EXE set "MAKE_EXE=%%M"
if defined MAKE_EXE (
    set "MAKE_ARGS=-j%NUMBER_OF_PROCESSORS%"
    goto run_build
)

goto choose_msvc_make

:prepare_mingw
rem Add the selected MinGW toolchain directory so gcc/g++ are available too.
for %%M in ("%MAKE_EXE%") do set "MINGW_BIN_DIR=%%~dpM"
set "PATH=%MINGW_BIN_DIR%;%PATH%"
goto run_build

:choose_msvc_make
for /f "delims=" %%M in ('where jom.exe 2^>nul') do if not defined MAKE_EXE set "MAKE_EXE=%%M"
if defined MAKE_EXE (
    set "MAKE_ARGS=-j%NUMBER_OF_PROCESSORS%"
    goto run_build
)

for /f "delims=" %%M in ('where nmake.exe 2^>nul') do if not defined MAKE_EXE set "MAKE_EXE=%%M"
if defined MAKE_EXE goto run_build

echo ERROR: No make tool compatible with this Qt installation was found.
echo.
echo For a MinGW Qt kit, install Qt's MinGW component or add mingw32-make.exe to PATH.
echo For an MSVC Qt kit, run this from a Visual Studio Developer Command Prompt
echo and make sure nmake.exe or jom.exe is available.
popd
exit /b 1

:run_build
echo [3/3] Building Q_ZodEngine with:
echo   %MAKE_EXE%
"%MAKE_EXE%" %MAKE_ARGS%
if errorlevel 1 (
    echo ERROR: Build failed.
    popd
    exit /b 1
)

popd
echo.
echo Build completed successfully.
echo Game binaries and libraries are written to:
echo   %ROOT%bin
exit /b 0

:bootstrap_qt
echo qmake was not found. Installing the Qt toolchain automatically...
echo.
echo This installs Qt 5.15.2 MinGW 8.1 (64-bit) for the current user under:
echo   %QZOD_QT_ROOT%
echo No administrator access is required.
echo.

if exist "%QZOD_QMAKE%" goto bootstrap_qmake_ready

if not exist "%QZOD_AQT_DIR%" mkdir "%QZOD_AQT_DIR%"
if errorlevel 1 (
    echo ERROR: Could not create the Qt bootstrap directory:
    echo   %QZOD_AQT_DIR%
    exit /b 1
)

if not exist "%QZOD_AQT_EXE%" (
    echo Downloading aqtinstall v3.3.0 bootstrapper...
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri $env:QZOD_AQT_URL -OutFile $env:QZOD_AQT_EXE"
    if errorlevel 1 (
        echo ERROR: Could not download the Qt bootstrapper.
        echo Check your internet connection and try again.
        exit /b 1
    )
)

set "AQT_HASH="
for /f "delims=" %%H in ('powershell.exe -NoLogo -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath $env:QZOD_AQT_EXE).Hash.ToLowerInvariant()"') do set "AQT_HASH=%%H"
if /I not "%AQT_HASH%"=="%QZOD_AQT_SHA256%" (
    echo ERROR: The downloaded aqtinstall bootstrapper failed SHA-256 verification.
    echo Expected: %QZOD_AQT_SHA256%
    echo Actual:   %AQT_HASH%
    del "%QZOD_AQT_EXE%" >nul 2>&1
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath $env:QZOD_AQT_EXE" >nul 2>&1

echo Installing Qt 5.15.2 Desktop MinGW 8.1 64-bit...
"%QZOD_AQT_EXE%" install-qt -O "%QZOD_QT_ROOT%" windows desktop 5.15.2 win64_mingw81
if errorlevel 1 goto qt_install_failed

:bootstrap_qmake_ready
if not exist "%QZOD_MINGW_BIN%\mingw32-make.exe" (
    echo Installing matching MinGW 8.1 compiler tools...
    "%QZOD_AQT_EXE%" install-tool -O "%QZOD_QT_ROOT%" windows desktop tools_mingw qt.tools.win64_mingw810
    if errorlevel 1 goto qt_install_failed
)

if not exist "%QZOD_QMAKE%" goto qt_install_failed
if not exist "%QZOD_MINGW_BIN%\mingw32-make.exe" goto qt_install_failed

set "QMAKE_EXE=%QZOD_QMAKE%"
set "PATH=%QZOD_MINGW_BIN%;%PATH%"
echo.
echo Qt toolchain installed successfully.
goto validate_qmake

:qt_install_failed
echo.
echo ERROR: Automatic Qt installation did not complete successfully.
echo Partial files, if any, are under:
echo   %QZOD_QT_ROOT%
echo.
echo Re-run build_game.bat to retry the download/install.
exit /b 1

:qmake_missing
echo ERROR: qmake was not found.
echo.
echo The script checked QMAKE_EXE, PATH, C:\Qt, %%USERPROFILE%%\Qt,
echo %%LOCALAPPDATA%%\Qt, and the automatic Qt_ZodEngine SDK location.
echo.
echo Automatic installation is disabled because QZOD_AUTO_INSTALL_QT=0.
echo Remove that setting and run build_game.bat again to auto-install Qt,
echo or point QMAKE_EXE at an existing qmake.exe.
exit /b 1
