# PowerShell script to clean up the problematic ios/ directory
# Run this script from the project root directory

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "iOS Directory Cleanup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if ios/ directory exists
if (-not (Test-Path ".\ios")) {
    Write-Host "ERROR: ios/ directory not found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found ios/ directory. Analyzing..." -ForegroundColor Yellow
Write-Host ""

# Show what will be removed
Write-Host "The following will be removed from git:" -ForegroundColor Yellow
Write-Host "- Entire ios/ directory (nested Flutter project)" -ForegroundColor White
Write-Host ""

# Count files
$fileCount = (git ls-files ios/ | Measure-Object).Count
Write-Host "Total tracked files in ios/: $fileCount" -ForegroundColor White
Write-Host ""

# Ask for confirmation
$confirmation = Read-Host "Do you want to proceed with removal? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Aborted by user." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Removing ios/ directory from git..." -ForegroundColor Green

# Remove from git
git rm -r ios/

Write-Host ""
Write-Host "✓ ios/ directory removed from git tracking" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Review the changes: git status" -ForegroundColor White
Write-Host "2. Commit the changes: git commit -m 'Remove nested Flutter project from ios/'" -ForegroundColor White
Write-Host "3. Push to remote: git push origin <branch-name>" -ForegroundColor White
Write-Host ""
Write-Host "Note: The ios/ directory still exists locally but is no longer tracked by git." -ForegroundColor Yellow
Write-Host "You can safely delete it from your filesystem if needed." -ForegroundColor Yellow

