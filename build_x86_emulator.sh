#!/usr/bin/env bash
set -e

# 1. Setup build environment
source build/envsetup.sh

# 2. Select x86_64 emulator lunch target
lunch lineage_sdk_phone_x86_64-userdebug

# 3. Start build with all available cores
m -j$(nproc)

echo "Build complete! To run the emulator, execute:"
echo "emulator -show-kernel"
