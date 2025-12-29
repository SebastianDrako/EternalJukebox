#!/data/data/com.termux/files/usr/bin/bash

# selfcompile.sh
# Script to compile Infinite Jukebox Local on Termux (Android)

set -e

echo "=== Infinite Jukebox Self-Compiler for Termux ==="

# 1. Update Termux packages
echo "[+] Updating Termux repositories..."
pkg update -y && pkg upgrade -y

# 2. Install dependencies
echo "[+] Installing dependencies (git, wget, openjdk-17, etc)..."
# openjdk-17 is usually recommended for recent Android Gradle builds
pkg install -y git wget unzip openjdk-17

# 3. Install Flutter
if ! command -v flutter &> /dev/null; then
    echo "[+] Flutter not found. Installing Flutter..."

    # Termux community often provides a flutter package, or we can clone from git.
    # The 'flutter' package in termux-packages is widely used.
    # But sometimes it's in a separate repo. Let's try standard pkg install first.
    if pkg install -y flutter; then
        echo "[+] Flutter installed via pkg."
    else
        echo "[!] 'pkg install flutter' failed. Attempting manual install from git..."

        # Determine architecture
        ARCH=$(uname -m)
        echo "[*] Architecture: $ARCH"

        # Manual clone of flutter is heavy but standard
        cd $HOME
        if [ -d "flutter" ]; then
            echo "[!] Flutter directory already exists in $HOME/flutter. Skipping clone."
        else
            git clone https://github.com/flutter/flutter.git --depth 1 -b stable
        fi

        export PATH="$HOME/flutter/bin:$PATH"

        # Add to shell config if not present
        if ! grep -q "flutter/bin" ~/.bashrc; then
             echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
        fi
        if ! grep -q "flutter/bin" ~/.zshrc; then
             echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
        fi
    fi
else
    echo "[+] Flutter is already installed."
fi

# 4. Check setup
echo "[+] Checking Flutter installation..."
flutter --version

# Termux often needs this permission fix for some builds
echo "[+] Fixing permissions..."
chmod +x android/gradlew 2>/dev/null || true

# 5. Build
echo "[+] Getting dependencies..."
flutter pub get

echo "[+] Building APK..."
# We explicitly set target platform and assume release
flutter build apk --release --target-platform android-arm64

echo "==========================================="
echo "Success!"
echo "APK should be at: build/app/outputs/flutter-apk/app-release.apk"
echo "You can open it from your file manager to install."
echo "==========================================="
