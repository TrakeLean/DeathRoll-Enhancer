#!/bin/bash
# Version update script - automatically updates all version references

if [ -z "$1" ]; then
    echo "Usage: ./update-version.sh <new-version>"
    echo "Example: ./update-version.sh 2.1.3"
    exit 1
fi

NEW_VERSION="$1"
echo "Updating to version $NEW_VERSION..."

# Update Core.lua
sed -i "s/DRE.version = \"[^\"]*\"/DRE.version = \"$NEW_VERSION\"/" Core.lua

# Update DeathRollEnhancer.toc
sed -i "s/## Version: [0-9.]*/## Version: $NEW_VERSION/" DeathRollEnhancer.toc
sed -i "s/Version [0-9.]*|r/Version $NEW_VERSION|r/" DeathRollEnhancer.toc

# Update README.md
sed -i "s/# DeathRoll Enhancer v[^ ]*/# DeathRoll Enhancer v$NEW_VERSION/" README.md
sed -i "s/Version-[^-]*-brightgreen/Version-$NEW_VERSION-brightgreen/" README.md

# Update CHANGELOG.md (add new section at top)
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" << EOF
# DeathRoll Enhancer - Changelog

## Version $NEW_VERSION - Bintes Edition

### Bug Fixes
- [Add your changes here]

### New Features  
- [Add your changes here]

---

EOF

# Append existing changelog (skip first line)
tail -n +2 CHANGELOG.md >> "$TEMP_FILE"
mv "$TEMP_FILE" CHANGELOG.md

echo "Version updated to $NEW_VERSION in all files!"
echo "Don't forget to:"
echo "1. Update CHANGELOG.md with actual changes"
echo "2. Test the addon"
echo "3. Commit and push: git add . && git commit -m 'Version $NEW_VERSION' && git push"