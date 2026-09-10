@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
cd /d "%ROOT%" || exit /b 1

echo [1/3] Checking Qt qmake...
if not defined QMAKE_EXE set "QMAKE_EXE=qmake"
"%QMAKE_EXE%" -v >nul 2>&1
if errorlevel 1 (
    echo ERROR: qmake was not found.
    echo.
    echo Put the Qt bin directory on PATH, or set QMAKE_EXE to the full path
    echo to qmake.exe before running this script.
    echo Example:
    echo   set QMAKE_EXE=C:\Qt\5.15.2\mingw81_64\bin\qmake.exe
    exit /b 1
)

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

where mingw32-make >nul 2>&1
if not errorlevel 1 (
    set "MAKE_EXE=mingw32-make"
    set "MAKE_ARGS=-j%NUMBER_OF_PROCESSORS%"
    goto run_build
)

where make >nul 2>&1
if not errorlevel 1 (
    set "MAKE_EXE=make"
    set "MAKE_ARGS=-j%NUMBER_OF_PROCESSORS%"
    goto run_build
)

goto choose_msvc_make

:choose_msvc_make
where jom >nul 2>&1
if not errorlevel 1 (
    set "MAKE_EXE=jom"
    set "MAKE_ARGS=-j%NUMBER_OF_PROCESSORS%"
    goto run_build
)

where nmake >nul 2>&1
if not errorlevel 1 (
    set "MAKE_EXE=nmake"
    goto run_build
)

if not defined MAKE_EXE (
    echo ERROR: No make tool compatible with this Qt installation was found.
    echo.
    echo For a MinGW Qt kit, add mingw32-make.exe to PATH.
    echo For an MSVC Qt kit, run this from a Visual Studio Developer Command Prompt
    echo and make sure nmake.exe or jom.exe is available.
    popd
    exit /b 1
)

:run_build
echo [3/3] Building Q_ZodEngine with %MAKE_EXE%...
%MAKE_EXE% %MAKE_ARGS%
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
