#!/bin/bash
# Bash script to clean up the problematic ios/ directory
# Run this script from the project root directory

echo "========================================"
echo "iOS Directory Cleanup Script"
echo "========================================"
echo ""

# Check if ios/ directory exists
if [ ! -d "./ios" ]; then
    echo "ERROR: ios/ directory not found!"
    exit 1
fi

echo "Found ios/ directory. Analyzing..."
echo ""

# Show what will be removed
echo "The following will be removed from git:"
echo "- Entire ios/ directory (nested Flutter project)"
echo ""

# Count files
fileCount=$(git ls-files ios/ | wc -l)
echo "Total tracked files in ios/: $fileCount"
echo ""

# Ask for confirmation
read -p "Do you want to proceed with removal? (yes/no): " confirmation
if [ "$confirmation" != "yes" ]; then
    echo "Aborted by user."
    exit 0
fi

echo ""
echo "Removing ios/ directory from git..."

# Remove from git
git rm -r ios/

echo ""
echo "✓ ios/ directory removed from git tracking"
echo ""
echo "Next steps:"
echo "1. Review the changes: git status"
echo "2. Commit the changes: git commit -m 'Remove nested Flutter project from ios/'"
echo "3. Push to remote: git push origin <branch-name>"
echo ""
echo "Note: The ios/ directory still exists locally but is no longer tracked by git."
echo "You can safely delete it from your filesystem if needed."

