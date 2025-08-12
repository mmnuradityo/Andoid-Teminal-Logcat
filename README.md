# Android Logcat Monitor

A powerful Android logcat monitoring tool with filtering and search capabilities.

## Prerequisites

### Install Android Platform Tools (ADB)

#### macOS
```bash
# Using Homebrew
brew install android-platform-tools

# Or download manually from:
# https://developer.android.com/studio/releases/platform-tools
```

#### Linux (Ubuntu/Debian)
```bash
# Install via package manager
sudo apt update
sudo apt install android-tools-adb

# Or install via snap
sudo snap install adb
```

#### Linux (CentOS/RHEL/Fedora)
```bash
# Fedora
sudo dnf install android-tools

# CentOS/RHEL (enable EPEL first)
sudo yum install epel-release
sudo yum install android-tools
```

### Verify ADB Installation
```bash
adb --version
```

## Installation

### 1. Clone Repository
```bash
git clone https://github.com/your-username/android-logcat-monitor.git
cd android-logcat-monitor
```

### 2. Setup Shell Configuration

#### macOS
**M1/M2 (zsh)** - Add to `~/.zshrc`:
```bash
alias android_logcat="YOUR_DIR/'Terminal Android Logcat'/android_logcat.sh"
```

**Intel (bash)** - Add to `~/.bash_profile`:
```bash
alias android_logcat="YOUR_DIR/'Terminal Android Logcat'/android_logcat.sh"
```

Example:
```bash
alias android_logcat="/Users/admin/tools/'Terminal Android Logcat'/android_logcat.sh"
```

#### Linux (Bash)
Add to `~/.bashrc`:
```bash
alias android_logcat="YOUR_DIR/'Terminal Android Logcat'/android_logcat.sh"
```

Example:
```bash
alias android_logcat="/home/user/tools/'Terminal Android Logcat'/android_logcat.sh"
```

### 3. Reload Shell Configuration
```bash
# macOS M1/M2 (zsh)
source ~/.zshrc

# macOS Intel (bash)
source ~/.bash_profile

# Linux
source ~/.bashrc
```

### 4. Make Script Executable
```bash
chmod +x "YOUR_DIR/Terminal Android Logcat/android_logcat.sh"
```

## Usage

### Start Monitoring
```bash
android_logcat <app_package_name> <device_id>
```

**Examples:**
```bash
# Monitor specific app
android_logcat com.example.myapp emulator-5554

# Check connected devices first
adb devices
```

### Filter Logs (Real-time)
```bash
android_logcat <session_id> --filter '<search_term>'
```

**Examples:**
```bash
android_logcat 12345 --filter 'error'
android_logcat 12345 --filter 'network'
android_logcat 12345 --filter 'MainActivity'
```

### Search Saved Logs
```bash
android_logcat <session_id> --search '<search_term>'
```

**Examples:**
```bash
android_logcat 12345 --search 'exception'
android_logcat 12345 --search 'timeout'
android_logcat 12345 --search 'retrofit'
```

### Clear Filter
```bash
android_logcat <session_id> --clear
```

### Help
```bash
android_logcat --help
```

## Features

- ✅ Real-time Android logcat monitoring
- ✅ Color-coded log levels (ERROR, WARNING, INFO)
- ✅ Network request/response highlighting (OkHttp)
- ✅ Fatal exception detection with formatted display
- ✅ Live filtering without stopping logcat
- ✅ Search through saved logs
- ✅ Cross-platform support (macOS & Linux)
- ✅ Session-based log management

## Troubleshooting

### Device Not Found
```bash
# Check connected devices
adb devices

# Restart ADB if needed
adb kill-server
adb start-server
```

### Permission Denied
```bash
# Make script executable
chmod +x android_logcat.sh
```

### Package Not Found
```bash
# List installed packages
adb shell pm list packages | grep <partial_package_name>

# Check if app is running
adb shell pidof <package_name>
```

## Log Files Location

Logs are saved in:
- **macOS/Linux**: `~/data_logs/android_logcat_<session_id>.txt`

## Requirements

- bash shell
- Android Debug Bridge (adb)
- Android device with USB debugging enabled