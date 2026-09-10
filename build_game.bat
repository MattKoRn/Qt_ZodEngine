@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
cd /d "%ROOT%" || exit /b 1

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

rem Finally search the most common per-machine and per-user Qt install roots.
for %%R in ("C:\Qt" "%USERPROFILE%\Qt" "%LOCALAPPDATA%\Qt") do (
    if exist "%%~R" (
        for /f "delims=" %%Q in ('dir /b /s "%%~R\qmake.exe" 2^>nul') do if not defined QMAKE_EXE set "QMAKE_EXE=%%Q"
    )
)

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

rem Qt's online installer normally keeps MinGW under C:\Qt\Tools rather than PATH.
for %%R in ("C:\Qt\Tools" "%USERPROFILE%\Qt\Tools" "%LOCALAPPDATA%\Qt\Tools") do (
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

:qmake_missing
echo ERROR: qmake was not found.
echo.
echo The script checked QMAKE_EXE, PATH, C:\Qt, %%USERPROFILE%%\Qt,
echo and %%LOCALAPPDATA%%\Qt.
echo.
echo If Qt is installed somewhere else, set QMAKE_EXE to qmake.exe first:
echo   set QMAKE_EXE=C:\Qt\5.15.2\mingw81_64\bin\qmake.exe
echo   build_game.bat
echo.
echo If no qmake.exe exists on this PC, install a Qt kit that includes qmake.
exit /b 1
