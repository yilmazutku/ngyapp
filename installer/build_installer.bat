@echo off
setlocal

echo Building Flutter Windows application...

rem Go to the folder where this script is (project root)
cd /d "%~dp0"

rem Try to kill any running instance of the app (optional)
rem taskkill /IM YourAppName.exe /F >nul 2>&1

rem Try to remove the build directory if it exists
if exist build (
    echo Deleting existing build directory...
    rmdir /s /q build
)

echo Running flutter clean...
flutter clean
if %ERRORLEVEL% NEQ 0 (
    echo Flutter clean failed with error code %ERRORLEVEL%
    pause
    exit /b %ERRORLEVEL%
)

echo Running flutter build windows --release...
flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo Flutter build failed with error code %ERRORLEVEL%
    pause
    exit /b %ERRORLEVEL%
)

echo Flutter build completed successfully.
echo.
echo Creating installer...

rem Go into installer folder temporarily
pushd installer

rem Check if NSIS is installed
where /q makensis.exe
if %ERRORLEVEL% NEQ 0 (
    echo NSIS is not installed or not in PATH.
    echo Please download and install NSIS from https://nsis.sourceforge.io/Download
    echo After installation, add the NSIS directory to your PATH environment variable.
    pause
    popd
    exit /b 1
)

makensis installer.nsi
if %ERRORLEVEL% NEQ 0 (
    echo Installer creation failed with error code %ERRORLEVEL%
    pause
    popd
    exit /b %ERRORLEVEL%
)

popd

echo.
echo Installer created successfully!
echo The installer can be found in the installer directory.
echo.
pause
endlocal
