#!/usr/bin/env bash
set -e

# 1. Initialize XephiraOS repository manifest
repo init -u https://github.com/XephiraOS/android.git -b lineage-23.2 --git-lfs

# 2. Sync repositories
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags

# 3. Setup build environment
source build/envsetup.sh

# 4. Select x86_64 emulator lunch target
lunch lineage_sdk_phone_x86_64-userdebug

# 5. Start build
m bacon -j$(nproc)

echo "Build complete! To run the emulator, execute:"
echo "emulator -show-kernel"
