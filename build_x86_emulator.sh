#!/usr/bin/env bash
# ==============================================================================
#  _  _          _     _            ___   ____  
# | || | ___ _ _| |_  (_)_ _ __ _  / _ \ / ___| 
#  \_, // -_) '_| ' \ | | '_/ _` || (_) |\___ \ 
#  /_/  \___|_| |_||_||_|_| \__,_| \___/ |____/ 
#
# XephiraOS 1.0 (Android 16 / LineageOS 23.2) - Aether Edition
# Automated x86_64 Android Virtual Device (AVD) Build System
# ==============================================================================
# Target: lineage_sdk_phone_x86_64-userdebug (QEMU Goldfish / Android Studio AVD)
# Alternative: lineage_cf_phone_x86_64-userdebug (Google Cuttlefish)
# Recommended Host: Ubuntu 22.04 / 24.04 LTS or WSL2 with >= 32GB RAM & 250GB Disk
# ==============================================================================

set -eo pipefail

# --- ANSI Color Palette ---
COLOR_RESET="\033[0m"
COLOR_BOLD="\033[1m"
COLOR_CYAN="\033[38;2;0;229;255m"      # Xephira Neon Cyan
COLOR_INDIGO="\033[38;2;99;102;241m"   # Xephira Indigo
COLOR_CRIMSON="\033[38;2;255;59;48m"   # Xephira Crimson
COLOR_GREEN="\033[38;2;52;199;89m"     # Radiant Green
COLOR_YELLOW="\033[38;2;255;204;0m"    # Warning Amber

log_info()    { echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $1"; }
log_step()    { echo -e "\n${COLOR_BOLD}${COLOR_INDIGO}==>${COLOR_RESET} ${COLOR_BOLD}$1${COLOR_RESET}"; }
log_success() { echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} ${COLOR_BOLD}$1${COLOR_RESET}"; }
log_warn()    { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"; }
log_error()   { echo -e "${COLOR_CRIMSON}[ERROR]${COLOR_RESET} $1" >&2; }

print_banner() {
    echo -e "${COLOR_CYAN}"
    echo "========================================================================"
    echo "         XephiraOS 1.0 (Android 16 / LineageOS 23.2)                    "
    echo "        x86_64 Emulator Build Automation & Launch Pipeline              "
    echo "========================================================================"
    echo -e "${COLOR_RESET}"
}

# --- Default Configuration ---
DO_SYNC=false
DO_CLEAN=false
DO_RUN=false
BUILD_CUTTLEFISH=false
LUNCH_TARGET="lineage_sdk_phone_x86_64-userdebug"
JOBS=$(nproc --all 2>/dev/null || echo 4)
CCACHE_SIZE="50G"

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sync)
            DO_SYNC=true
            shift
            ;;
        --clean)
            DO_CLEAN=true
            shift
            ;;
        --run)
            DO_RUN=true
            shift
            ;;
        --cuttlefish)
            BUILD_CUTTLEFISH=true
            LUNCH_TARGET="lineage_cf_phone_x86_64-userdebug"
            shift
            ;;
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        --ccache)
            CCACHE_SIZE="$2"
            shift 2
            ;;
        -h|--help)
            print_banner
            echo "Usage: ./build_x86_emulator.sh [options]"
            echo ""
            echo "Options:"
            echo "  --sync            Sync source repositories before building"
            echo "  --clean           Clean output artifacts (make clobber) before build"
            echo "  --run             Immediately boot the x86_64 emulator upon build completion"
            echo "  --cuttlefish      Target Google Cuttlefish (lineage_cf_phone_x86_64) instead of Goldfish SDK"
            echo "  -j, --jobs N      Specify parallel make jobs (default: ${JOBS})"
            echo "  --ccache SIZE     Set ccache max size (default: ${CCACHE_SIZE})"
            echo "  -h, --help        Show this help message"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            echo "Run './build_x86_emulator.sh --help' for usage."
            exit 1
            ;;
    esac
done

print_banner

# --- 1. Host Architecture & Environment Validation ---
log_step "Step 1: Validating Host Build Environment"

if [[ "$(uname -s)" != "Linux" ]]; then
    log_error "Android 16 ROM builds require a 64-bit Linux host (Ubuntu 22.04/24.04 LTS or Debian 12 / WSL2)."
    log_error "Current OS reported: $(uname -s)"
    exit 1
fi

AVAILABLE_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
AVAILABLE_RAM_GB=$((AVAILABLE_RAM_KB / 1024 / 1024))
log_info "Detected Host RAM: ${AVAILABLE_RAM_GB} GB"
if [[ $AVAILABLE_RAM_GB -lt 16 ]]; then
    log_warn "Host RAM is under 16GB. Android 16 Soong/Ninja build may trigger OOM. Recommended >= 32GB."
fi

# Check required utilities
REQUIRED_CMDS=("git" "curl" "python3" "tar" "gzip" "rsync" "make")
MISSING_CMDS=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_CMDS+=("$cmd")
    fi
done

if [[ ${#MISSING_CMDS[@]} -gt 0 ]]; then
    log_error "Missing required build dependencies: ${MISSING_CMDS[*]}"
    log_info "Install required packages on Ubuntu/Debian:"
    echo "sudo apt-get update && sudo apt-get install -y bc bison build-essential ccache curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc zip zlib1g-dev openjdk-17-jdk python3"
    exit 1
fi
log_success "Host utilities and system prerequisites validated."

# --- 2. Ccache Acceleration Configuration ---
log_step "Step 2: Configuring Ccache Acceleration"
export USE_CCACHE=1
export CCACHE_COMPRESS=1
export CCACHE_EXEC=$(command -v ccache || echo "/usr/bin/ccache")
if command -v ccache &>/dev/null; then
    ccache -M "$CCACHE_SIZE" >/dev/null 2>&1 || true
    log_success "Ccache enabled: limit set to ${CCACHE_SIZE} at ${CCACHE_EXEC}"
else
    log_warn "ccache not found in PATH. Build will proceed without compiler caching."
fi

# --- 3. Repository Synchronization (Optional) ---
if [[ "$DO_SYNC" == true ]]; then
    log_step "Step 3: Synchronizing XephiraOS Repositories"
    if ! command -v repo &>/dev/null; then
        log_warn "'repo' tool not found in PATH. Downloading standalone repo binary..."
        mkdir -p ~/bin
        curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
        chmod a+x ~/bin/repo
        export PATH=~/bin:$PATH
    fi
    log_info "Executing repo sync with lineage-23.2 manifest..."
    repo sync -c --force-sync --no-clone-bundle --no-tags -j"$JOBS"
    log_success "Source tree synchronized successfully."
else
    log_step "Step 3: Repository Synchronization skipped (pass --sync to enable)"
fi

# --- 4. Setup Build Environment ---
log_step "Step 4: Initializing Build Environment & Lunch Target"
if [[ ! -f "build/envsetup.sh" ]]; then
    log_error "build/envsetup.sh not found in $(pwd)."
    log_error "Please run this script from the root of your XephiraOS source tree."
    exit 1
fi

source build/envsetup.sh
log_info "Configuring target: ${COLOR_CYAN}${LUNCH_TARGET}${COLOR_RESET}"
lunch "${LUNCH_TARGET}"
log_success "Lunch configuration set for ${LUNCH_TARGET}."

# --- 5. Optional Clean ---
if [[ "$DO_CLEAN" == true ]]; then
    log_step "Step 5: Cleaning output tree"
    make clobber
    log_success "Output tree cleaned."
fi

# --- 6. Compilation ---
log_step "Step 6: Compiling XephiraOS x86_64 Target Images"
log_info "Parallel Threads : ${JOBS}"
log_info "Target Platform  : ${LUNCH_TARGET}"
log_info "Start Timestamp  : $(date '+%Y-%m-%d %H:%M:%S')"

START_TIME=$(date +%s)

# Compile primary emulator target
if [[ "$BUILD_CUTTLEFISH" == true ]]; then
    m -j"$JOBS"
else
    # Build complete emulator system, vendor, boot, and sdk addon images
    m -j"$JOBS" qemu-props systemimage vendorimage bootimage userdataimage
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))

log_success "Build completed in ${HOURS}h ${MINUTES}m ${SECONDS}s!"

# Determine product out directory
PRODUCT_OUT="${ANDROID_PRODUCT_OUT:-out/target/product/lineage_sdk_phone_x86_64}"
log_info "Output artifacts located in: ${COLOR_CYAN}${PRODUCT_OUT}${COLOR_RESET}"
echo -e "${COLOR_BOLD}Generated Images:${COLOR_RESET}"
ls -lh "${PRODUCT_OUT}"/*.img 2>/dev/null || true

# --- 7. Run Emulator (Optional or via --run) ---
if [[ "$DO_RUN" == true ]]; then
    log_step "Step 7: Launching XephiraOS x86_64 Emulator"
    if [[ "$BUILD_CUTTLEFISH" == true ]]; then
        log_info "Launching Cuttlefish virtual device..."
        launch_cvd
    else
        log_info "Launching Android SDK Goldfish Emulator..."
        if command -v emulator &>/dev/null; then
            emulator -show-kernel -no-audio -verbose
        else
            log_warn "'emulator' binary not found in PATH."
            log_info "Run with host Android SDK: emulator -sysdir ${PRODUCT_OUT} -system ${PRODUCT_OUT}/system.img"
        fi
    fi
else
    echo ""
    echo -e "${COLOR_GREEN}========================================================================${COLOR_RESET}"
    echo -e "${COLOR_BOLD}To launch your compiled XephiraOS x86_64 Emulator:${COLOR_RESET}"
    echo -e "  1. Set environment:  ${COLOR_CYAN}source build/envsetup.sh && lunch ${LUNCH_TARGET}${COLOR_RESET}"
    echo -e "  2. Run Emulator:     ${COLOR_CYAN}emulator -show-kernel${COLOR_RESET}"
    echo -e "  Or run:              ${COLOR_CYAN}./build_x86_emulator.sh --run${COLOR_RESET}"
    echo -e "${COLOR_GREEN}========================================================================${COLOR_RESET}"
fi
