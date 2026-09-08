#!/usr/bin/env bash
set -e

# 1. Initialize XephiraOS repository manifest
repo init -u https://github.com/XephiraOS/android.git -b lineage-23.2 --git-lfs --no-clone-bundle --depth=1; \

# 2. Sync repositories
/opt/crave/resync.sh; \

# 3. Setup build environment
source build/envsetup.sh; \

# 4. Select x86_64 emulator lunch target
breakfast sdk_phone_x86_64 eng; \

# 5. Start build
mka
