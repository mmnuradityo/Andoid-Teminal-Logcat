#!/bin/bash
# Android Logcat Auto Runner - New Version
# Simple and reliable approach

# Configuration
DEFAULT_PACKAGE="com.qiscus.qismo.chat.debug"
DEFAULT_DEVICE="emulator-5554"
LOGCAT_DIR="./"

# Global variables
SELECTED_DEVICE=""
DEVICE_TYPE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_step() {
    echo -e "${BLUE}🔥 $1${NC}"
}

# Check if ADB is available
check_adb() {
    if ! command -v adb >/dev/null 2>&1; then
        print_error "ADB not found! Please install Android SDK Platform Tools"
        return 1
    fi
    return 0
}

# Get all connected devices
get_connected_devices() {
    adb devices 2>/dev/null | grep -E "device$" | awk '{print $1}'
}

# Check if device is emulator
is_emulator() {
    local device="$1"
    [[ "$device" =~ ^emulator- ]]
}

# Find best available device
find_best_device() {
    local requested="$1"
    local devices
    
    print_step "Scanning for devices..."
    
    devices=$(get_connected_devices)
    
    if [ -z "$devices" ]; then
        print_warning "No connected devices found"
        return 1
    fi
    
    print_info "Found connected devices:"
    local count=1
    for device in $devices; do
        if is_emulator "$device"; then
            echo "  $count. 💻 $device (Emulator)"
        else
            echo "  $count. 📱 $device (Real Device)"
        fi
        count=$((count + 1))
    done
    
    # Check if requested device exists
    for device in $devices; do
        if [ "$device" = "$requested" ]; then
            SELECTED_DEVICE="$requested"
            if is_emulator "$requested"; then
                DEVICE_TYPE="emulator"
            else
                DEVICE_TYPE="real"
            fi
            print_success "Using requested device: $requested"
            return 0
        fi
    done
    
    # Find first real device
    for device in $devices; do
        if ! is_emulator "$device"; then
            SELECTED_DEVICE="$device"
            DEVICE_TYPE="real"
            print_success "Using real device: $device"
            return 0
        fi
    done
    
    # Use first emulator
    SELECTED_DEVICE=$(echo "$devices" | head -n 1)
    DEVICE_TYPE="emulator"
    print_success "Using emulator: $SELECTED_DEVICE"
    return 0
}

# Get list of AVDs
get_avd_list() {
    emulator -list-avds 2>/dev/null
}

# Start specific AVD
start_avd() {
    local avd_name="$1"
    
    print_step "Starting AVD: $avd_name"
    
    # Start emulator in background
    emulator -avd "$avd_name" -netdelay none -netspeed full >/dev/null 2>&1 &
    local pid=$!
    
    print_info "Emulator PID: $pid"
    print_info "Waiting for emulator to start (max 90 seconds)..."
    
    local timeout=45  # 90 seconds total (45 x 2)
    local count=0
    
    while [ $count -lt $timeout ]; do
        sleep 2
        count=$((count + 1))
        
        # Check if new emulator appeared
        local new_devices
        new_devices=$(get_connected_devices | grep emulator)
        
        if [ -n "$new_devices" ]; then
            # Get the latest emulator
            local latest_emulator
            latest_emulator=$(echo "$new_devices" | tail -n 1)
            
            print_success "Emulator detected: $latest_emulator"
            print_info "Waiting for boot completion..."
            
            # Wait for boot
            if adb -s "$latest_emulator" wait-for-device 2>/dev/null; then
                local boot_count=0
                while [ $boot_count -lt 30 ]; do  # 60 seconds max
                    sleep 2
                    boot_count=$((boot_count + 1))
                    
                    local boot_status
                    boot_status=$(adb -s "$latest_emulator" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')
                    
                    if [ "$boot_status" = "1" ]; then
                        print_success "Emulator ready: $latest_emulator"
                        SELECTED_DEVICE="$latest_emulator"
                        DEVICE_TYPE="emulator"
                        return 0
                    fi
                done
            fi
        fi
        
        echo -n "."
    done
    
    echo ""
    print_error "Emulator failed to start within timeout"
    
    # Kill hanging process
    if kill -0 "$pid" 2>/dev/null; then
        print_info "Killing hanging emulator process..."
        kill "$pid" 2>/dev/null
    fi
    
    return 1
}

# Try to start any available AVD
start_any_avd() {
    print_step "No devices connected. Trying to start emulator..."
    
    local avds
    avds=$(get_avd_list)
    
    if [ -z "$avds" ]; then
        print_error "No AVDs found!"
        print_info "Create one in Android Studio: Tools > AVD Manager"
        return 1
    fi
    
    print_info "Available AVDs:"
    local count=1
    echo "$avds" | while read -r avd; do
        [ -n "$avd" ] && echo "  $count. $avd"
        count=$((count + 1))
    done
    
    # Try each AVD
    echo "$avds" | while read -r avd; do
        if [ -n "$avd" ]; then
            if start_avd "$avd"; then
                return 0
            fi
            print_warning "Failed to start $avd, trying next..."
        fi
    done
    
    print_error "All AVDs failed to start"
    return 1
}

# Verify package exists on device
verify_package() {
    local package="$1"
    local device="$2"
    
    print_step "Verifying package: $package"
    
    if ! adb -s "$device" shell echo "test" >/dev/null 2>&1; then
        print_error "Cannot communicate with device: $device"
        return 1
    fi
    
    if adb -s "$device" shell pm list packages | grep -q "^package:$package$"; then
        print_success "Package found: $package"
        return 0
    else
        print_error "Package not found: $package"
        print_info "Available debug packages:"
        adb -s "$device" shell pm list packages | grep debug | head -5 | sed 's/package:/  /'
        return 1
    fi
}

# Fix background restrictions for Qiscus
fix_qiscus_background() {
    local package="$1"
    local device="$2"
    
    print_step "Fixing Qiscus background restrictions..."
    
    print_info "Launching app..."
    adb -s "$device" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    sleep 2
    
    print_info "Disabling battery optimization..."
    adb -s "$device" shell dumpsys deviceidle whitelist +"$package" >/dev/null 2>&1
    
    print_info "Allowing background activity..."
    adb -s "$device" shell cmd appops set "$package" RUN_IN_BACKGROUND allow >/dev/null 2>&1
    adb -s "$device" shell cmd appops set "$package" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
    
    print_success "Background restrictions fixed"
}

# Main function
run_logcat() {
    local package="${1:-$DEFAULT_PACKAGE}"
    local requested_device="${2:-$DEFAULT_DEVICE}"
    
    echo "=========================================="
    echo "🔥 Android Logcat Auto Runner"
    echo "📦 Package: $package"
    echo "📱 Target Device: $requested_device"
    echo "=========================================="
    
    # Check ADB
    if ! check_adb; then
        return 1
    fi
    
    # Find device
    if find_best_device "$requested_device"; then
        print_success "Selected device: $SELECTED_DEVICE ($DEVICE_TYPE)"
    else
        # Try to start emulator
        if start_any_avd; then
            print_success "Emulator started: $SELECTED_DEVICE"
        else
            print_error "No devices available and cannot start emulator"
            return 1
        fi
    fi
    
    # Verify package
    if ! verify_package "$package" "$SELECTED_DEVICE"; then
        return 1
    fi
    
    # Fix Qiscus background issues
    if echo "$package" | grep -q "qiscus"; then
        fix_qiscus_background "$package" "$SELECTED_DEVICE"
    fi
    
    # Check for logcat script
    print_step "Looking for logcat script..."
    
    if [ ! -d "$LOGCAT_DIR" ]; then
        print_error "Directory not found: $LOGCAT_DIR"
        return 1
    fi
    
    cd "$LOGCAT_DIR" || {
        print_error "Cannot enter directory: $LOGCAT_DIR"
        return 1
    }
    
    if [ ! -f "./android_logcat.sh" ]; then
        print_error "Script not found: ./android_logcat.sh"
        print_info "Current directory: $(pwd)"
        print_info "Available scripts:"
        ls -la *.sh 2>/dev/null || echo "  No .sh files found"
        cd - >/dev/null
        return 1
    fi
    
    # Execute logcat
    print_step "STARTING LOGCAT"
    echo "Command: ./android_logcat.sh '$package' '$SELECTED_DEVICE'"
    echo "=========================================="
    
    ./android_logcat.sh "$package" "$SELECTED_DEVICE"
    local exit_code=$?
    
    cd - >/dev/null
    
    if [ $exit_code -eq 0 ]; then
        print_success "Logcat completed successfully"
    else
        print_warning "Logcat exited with code: $exit_code"
    fi
    
    return $exit_code
}

# Helper functions for command line usage

list_devices() {
    print_step "Connected Devices"
    check_adb || return 1
    
    local devices
    devices=$(get_connected_devices)
    
    if [ -z "$devices" ]; then
        print_warning "No devices connected"
        return 1
    fi
    
    local count=1
    for device in $devices; do
        if is_emulator "$device"; then
            echo "  $count. 💻 $device (Emulator)"
        else
            echo "  $count. 📱 $device (Real Device)"
        fi
        count=$((count + 1))
    done
}

list_avds() {
    print_step "Available AVDs"
    
    local avds
    avds=$(get_avd_list)
    
    if [ -z "$avds" ]; then
        print_warning "No AVDs found"
        print_info "Create one in Android Studio: Tools > AVD Manager"
        return 1
    fi
    
    local count=1
    echo "$avds" | while read -r avd; do
        if [ -n "$avd" ]; then
            echo "  $count. $avd"
            count=$((count + 1))
        fi
    done
}

kill_emulators() {
    print_step "Stopping all emulators..."
    
    local emulators
    emulators=$(get_connected_devices | grep emulator)
    
    if [ -z "$emulators" ]; then
        print_info "No running emulators found"
        return 0
    fi
    
    for emu in $emulators; do
        print_info "Stopping $emu..."
        adb -s "$emu" emu kill 2>/dev/null
    done
    
    print_success "All emulators stopped"
}

show_help() {
    echo "🔥 Android Logcat Auto Runner"
    echo "============================="
    echo ""
    echo "Usage:"
    echo "  ./android_logcat_runner.sh [package] [device]"
    echo ""
    echo "Commands:"
    echo "  ./android_logcat_runner.sh                    # Run with defaults"
    echo "  ./android_logcat_runner.sh com.my.app         # Custom package"
    echo "  ./android_logcat_runner.sh com.my.app emulator-5554  # Custom device"
    echo ""
    echo "Special commands:"
    echo "  ./android_logcat_runner.sh devices            # List connected devices"
    echo "  ./android_logcat_runner.sh avds               # List available AVDs"
    echo "  ./android_logcat_runner.sh kill               # Stop all emulators"
    echo "  ./android_logcat_runner.sh help               # Show this help"
    echo ""
    echo "Examples:"
    echo "  ./android_logcat_runner.sh"
    echo "  ./android_logcat_runner.sh com.qiscus.qismo.chat.debug"
    echo "  ./android_logcat_runner.sh com.myapp.debug RR8R4086JFV"
}

# Main script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        help|-h|--help)
            show_help
            ;;
        devices|list)
            list_devices
            ;;
        avds)
            list_avds
            ;;
        kill|stop)
            kill_emulators
            ;;
        "")
            run_logcat
            ;;
        *)
            run_logcat "$1" "$2"
            ;;
    esac
fi