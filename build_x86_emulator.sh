#!/usr/bin/env bash
set -e

# 1. Sync repositories
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags

# 2. Setup build environment
source build/envsetup.sh

# 3. Select x86_64 emulator lunch target
lunch lineage_sdk_phone_x86_64-userdebug

# 4. Start build
m bacon -j$(nproc)

echo "Build complete! To run the emulator, execute:"
echo "emulator -show-kernel"
