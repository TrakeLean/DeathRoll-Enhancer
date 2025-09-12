# DeathRoll Enhancer - Release Process

## Steps to Create a New Version Release

### 1. Update Version Numbers
- **Core.lua**: Update `DRE.version = "X.X.X"`
- **DeathRollEnhancer.toc**: 
  - Update `## Version: X.X.X`
  - Update the `## Notes:` section with new version info and features

### 2. Update Documentation
- **CHANGELOG.md**: Add new version section at the top with:
  - Version number and edition name
  - Bug fixes (if any)
  - New features (if any)
  - Breaking changes (if any)

### 3. Create Version Archive
1. Create a temporary folder named `DeathRollEnhancer`
2. Copy all the important files to the `DeathRollEnhancer` folder:
   - Core.lua, Database.lua, UI.lua, Events.lua, Minimap.lua
   - DeathRollEnhancer.toc
   - Media folder (contains textures/icons)
3. Create a zip archive of the entire `DeathRollEnhancer` folder using PowerShell: 
   ```powershell
   Compress-Archive -Path .\DeathRollEnhancer -DestinationPath .\versions\DeathRollEnhancer VX.X.X - Edition Name.zip -Force
   ```
   - Replace `VX.X.X` with the new version number
   - Replace `Edition_Name` with a descriptive name (e.g., "Bintes EDITion", "Gold Tracking Fix Edition")
4. Clean up the temporary folder:
   ```powershell
   Remove-Item -Recurse -Force .\DeathRollEnhancer
   ```

### 4. Verify Archive
- Check that the zip file was created in the `versions/` folder
- **Important**: When extracted, the zip should create a `DeathRollEnhancer` folder containing all the addon files
- This allows users to extract directly to their `Interface/AddOns/` folder

### 5. Push to GitHub
Commit and push all changes to the repository:
```bash
git add .
git commit -m "Version X.X.X - Edition Name"
git push origin main
```

## File Inclusion Rules
**Included in release:**
- All .lua files (Core.lua, Database.lua, UI.lua, Events.lua, Minimap.lua)
- DeathRollEnhancer.toc file

**Excluded from release:**
- .git folder and git files
- .vscode folder
- versions/ folder contents
- .md files (README, CHANGELOG, etc.)
- update-version scripts (.ps1, .sh)
- Development and documentation files

## Version Naming Convention
Format: `DeathRollEnhancer VX.X.X - Edition Name.zip`

Examples:
- `DeathRollEnhancer V2.1.4 - Bintes EDITion.zip`
- `DeathRollEnhancer V2.1.5 - Gold Tracking Fix Edition.zip`

## Quick Checklist
- [ ] Update version in Core.lua
- [ ] Update version and notes in .toc file
- [ ] Add changelog entry
- [ ] Create DeathRollEnhancer folder with all files
- [ ] Create zip archive with PowerShell command
- [ ] Verify zip contains correct files
- [ ] Commit and push to GitHub
- [ ] Test the release (optional but recommended)