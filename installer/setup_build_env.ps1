# PowerShell script to set up proper build environment
# Run this script as administrator if you encounter network issues during the build process

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "You need to run this script as an Administrator. Right-click the script and select 'Run as Administrator'."
    Exit
}

Write-Host "Setting up build environment for Flutter Windows application..." -ForegroundColor Green

# Function to check internet connectivity
function Test-InternetConnection {
    try {
        $response = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing
        return $true
    }
    catch {
        return $false
    }
}

# Check internet connectivity
Write-Host "Checking internet connectivity..." -ForegroundColor Yellow
$hasInternet = Test-InternetConnection
if (-not $hasInternet) {
    Write-Host "Internet connection issue detected." -ForegroundColor Red
    
    # Ask if user wants to set up a proxy
    $setupProxy = Read-Host "Do you want to set up a proxy configuration? (y/n)"
    if ($setupProxy -eq "y") {
        $proxyAddress = Read-Host "Enter proxy address (e.g., http://proxy.example.com:8080)"
        
        # Set system-wide proxy
        [Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyAddress, [System.EnvironmentVariableTarget]::Machine)
        [Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyAddress, [System.EnvironmentVariableTarget]::Machine)
        
        # Set Git proxy
        git config --global http.proxy $proxyAddress
        git config --global https.proxy $proxyAddress
        
        # Set Flutter proxy
        $flutterDir = [System.IO.Path]::Combine($env:LOCALAPPDATA, "flutter", ".flutter_tool_state")
        if (!(Test-Path $flutterDir)) {
            New-Item -ItemType Directory -Force -Path $flutterDir
        }
        
        Write-Host "Proxy configuration set. Please restart any open terminals or applications for changes to take effect." -ForegroundColor Green
    }
}

# Check for Flutter Windows dependencies
Write-Host "Checking Flutter Windows dependencies..." -ForegroundColor Yellow
flutter config --enable-windows-desktop
flutter doctor

# Improve network reliability for Flutter
Write-Host "Setting network timeout settings for Flutter..." -ForegroundColor Yellow
$settingsFile = "C:\Users\$env:USERNAME\.gradle\gradle.properties"
$settingsDir = "C:\Users\$env:USERNAME\.gradle"

if (!(Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Force -Path $settingsDir
}

$gradleSettings = @"
org.gradle.jvmargs=-Xmx1536M
org.gradle.parallel=true
org.gradle.daemon=false
org.gradle.configureondemand=true
connectionTimeout=180000
socketTimeout=180000
"@

Set-Content -Path $settingsFile -Value $gradleSettings -Force

# Fix Firebase connectivity issues if necessary
Write-Host "Setting up Firebase configuration for better connectivity..." -ForegroundColor Yellow
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.googleapis.com"
[Environment]::SetEnvironmentVariable("FLUTTER_STORAGE_BASE_URL", "https://storage.googleapis.com", [System.EnvironmentVariableTarget]::User)

# Final check
Write-Host "Environment setup complete. You should now be able to build the Flutter Windows application." -ForegroundColor Green
Write-Host "Run the build_installer.bat script to create the installer." -ForegroundColor Green 