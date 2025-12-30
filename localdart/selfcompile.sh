#!/data/data/com.termux/files/usr/bin/bash

# selfcompile.sh
# Compiles Infinite Jukebox Local using proot-distro (Ubuntu) on Termux.

set -e

DISTRO="ubuntu"
PROJECT_DIR=$(pwd)
WORKSPACE_DIR="$HOME/flutter_workspace"

echo "=== Infinite Jukebox Self-Compiler (via proot-distro/ubuntu) ==="

# 1. Setup Host (Termux)
echo "[Host] Checking requirements..."
if ! command -v proot-distro &> /dev/null; then
    echo "[Host] Installing proot-distro..."
    pkg update -y && pkg install -y proot-distro
fi

if ! proot-distro list | grep -q "$DISTRO (installed)"; then
    echo "[Host] Installing $DISTRO..."
    proot-distro install $DISTRO
fi

# Create workspace for persistence
mkdir -p "$WORKSPACE_DIR"

# Create the internal build script
cat << 'EOF' > "$WORKSPACE_DIR/build_internal.sh"
#!/bin/bash
set -e

# Configuration
SDK_ROOT="/workspace/sdk"
FLUTTER_ROOT="$SDK_ROOT/flutter"
ANDROID_HOME="$SDK_ROOT/android"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip"
PROJECT_ROOT="/project"

echo "[Guest] Updating system..."
apt-get update
# Dependencies for Flutter and Android SDK
apt-get install -y git wget curl unzip xz-utils openjdk-17-jdk

# Setup directories
mkdir -p "$SDK_ROOT"
mkdir -p "$ANDROID_HOME/cmdline-tools"

# 1. Install Android Command Line Tools
if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
    echo "[Guest] Downloading Android Command Line Tools..."
    cd "$SDK_ROOT"
    wget -q -O cmdline-tools.zip "$CMDLINE_TOOLS_URL"
    unzip -q cmdline-tools.zip
    # Move to correct structure: cmdline-tools/latest/bin
    mv cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
    rm cmdline-tools.zip
else
    echo "[Guest] Android Command Line Tools already installed."
fi

export ANDROID_HOME="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# 2. Install Flutter
if [ ! -d "$FLUTTER_ROOT" ]; then
    echo "[Guest] Cloning Flutter SDK..."
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_ROOT"
else
    echo "[Guest] Flutter SDK already installed."
fi

export PATH="$FLUTTER_ROOT/bin:$PATH"

# 3. Configure
echo "[Guest] Configuring Flutter..."
git config --global --add safe.directory "$FLUTTER_ROOT"
git config --global --add safe.directory "$PROJECT_ROOT"

# Pre-download Flutter artifacts
flutter precache

# Accept Licenses
echo "[Guest] Accepting Android Licenses..."
yes | flutter doctor --android-licenses || true

# Check status
flutter doctor

# 4. Build
echo "[Guest] Building APK..."
cd "$PROJECT_ROOT"
flutter pub get

# Note: We build for arm64-v8a usually for modern phones.
# If this fails due to gradle connectivity, ensure internet is available.
flutter build apk --release

echo "[Guest] Build Complete."
EOF

chmod +x "$WORKSPACE_DIR/build_internal.sh"

echo "[Host] Launching build inside $DISTRO..."

# We bind mount:
# 1. The project directory to /project
# 2. The workspace directory (SDKs) to /workspace
# This ensures that SDK downloads persist between runs, saving data/time.

proot-distro login "$DISTRO" \
    --bind "$PROJECT_DIR:/project" \
    --bind "$WORKSPACE_DIR:/workspace" \
    -- bash /workspace/build_internal.sh

echo "==========================================="
echo "Done!"
echo "If successful, APK is at: $PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
echo "==========================================="
