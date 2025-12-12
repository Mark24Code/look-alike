#!/bin/bash

# Look-Alike Multi-Platform Packaging Script
# Builds and packages the application for Windows, Mac Intel, and Mac ARM

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="look-alike"
VERSION="1.0.0"
DIST_DIR="dist"
CLIENT_DIR="client"
SERVER_DIR="go-server"

# Platform configurations
# Format: "GOOS/GOARCH/output_suffix/archive_name"
PLATFORMS=(
    "windows/amd64/look-alike.exe/look-alike-windows-x64"
    "darwin/amd64/look-alike/look-alike-macos-x64"
    "darwin/arm64/look-alike/look-alike-macos-arm64"
)

# Print colored message
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Print section header
print_header() {
    echo ""
    print_msg "$BLUE" "=========================================="
    print_msg "$BLUE" "$1"
    print_msg "$BLUE" "=========================================="
    echo ""
}

# Build frontend
build_frontend() {
    print_header "Building Frontend"

    cd "$CLIENT_DIR"

    # Check if node_modules exists
    if [ ! -d "node_modules" ]; then
        print_msg "$YELLOW" "node_modules not found, installing dependencies..."
        npm install
    fi

    print_msg "$GREEN" "Building frontend..."
    npm run build

    if [ ! -d "dist" ]; then
        print_msg "$RED" "Frontend build failed: dist directory not found"
        exit 1
    fi

    cd ..
    print_msg "$GREEN" "✓ Frontend build complete"
}

# Build backend for specific platform
build_backend() {
    local goos=$1
    local goarch=$2
    local output=$3
    local platform_name=$4

    print_msg "$GREEN" "Building backend for ${platform_name}..."

    cd "$SERVER_DIR"

    # Set environment variables and build
    GOOS=$goos GOARCH=$goarch CGO_ENABLED=1 GOPROXY=https://goproxy.cn,direct \
        go build -ldflags="-s -w" -o "../$output" ./cmd/server

    if [ $? -ne 0 ]; then
        print_msg "$RED" "Backend build failed for ${platform_name}"
        cd ..
        return 1
    fi

    cd ..
    print_msg "$GREEN" "✓ Backend build complete for ${platform_name}"
    return 0
}

# Create package for specific platform
create_package() {
    local goos=$1
    local goarch=$2
    local binary_name=$3
    local archive_name=$4

    local platform_display
    if [ "$goos" = "windows" ]; then
        platform_display="Windows x64"
    elif [ "$goos" = "darwin" ] && [ "$goarch" = "amd64" ]; then
        platform_display="macOS Intel (x64)"
    elif [ "$goos" = "darwin" ] && [ "$goarch" = "arm64" ]; then
        platform_display="macOS Apple Silicon (ARM64)"
    fi

    print_msg "$YELLOW" "Creating package for ${platform_display}..."

    # Create temporary build directory
    local build_dir="${DIST_DIR}/${archive_name}"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    # Copy binary
    cp "$binary_name" "$build_dir/"

    # Copy frontend dist
    cp -r "${CLIENT_DIR}/dist" "$build_dir/client/"

    # Create db directory (will be auto-created by app but good to have)
    mkdir -p "$build_dir/db"

    # Create README
    cat > "$build_dir/README.txt" << EOF
Look-Alike Image Comparison Tool v${VERSION}
=============================================

Platform: ${platform_display}

Quick Start:
-----------
1. Double-click the executable to start the server
2. Open your browser and navigate to: http://localhost:4568
3. The database will be automatically created in the 'db' folder

Configuration:
-------------
- Default port: 4568
- You can change the port by setting the PORT environment variable

Data:
-----
- All data is stored in the 'db' folder
- The database is created automatically on first run
- You can delete the database to reset all data

Support:
--------
For issues and questions, please contact support.

Built on: $(date)
EOF

    # Create archive
    cd "$DIST_DIR"
    if [ "$goos" = "windows" ]; then
        # Create ZIP for Windows
        print_msg "$GREEN" "Creating ${archive_name}.zip..."
        zip -rq "${archive_name}.zip" "$archive_name"
        print_msg "$GREEN" "✓ Created ${archive_name}.zip"
    else
        # Create tar.gz for macOS
        print_msg "$GREEN" "Creating ${archive_name}.tar.gz..."
        tar -czf "${archive_name}.tar.gz" "$archive_name"
        print_msg "$GREEN" "✓ Created ${archive_name}.tar.gz"
    fi
    cd ..

    # Clean up temporary directory
    rm -rf "$build_dir"

    # Clean up binary
    rm -f "$binary_name"
}

# Main function
main() {
    local target_platform=$1

    print_header "Look-Alike Multi-Platform Packaging"
    print_msg "$BLUE" "Version: ${VERSION}"
    echo ""

    # Clean and create dist directory
    print_msg "$YELLOW" "Cleaning previous builds..."
    rm -rf "$DIST_DIR"
    mkdir -p "$DIST_DIR"

    # Build frontend once (shared by all platforms)
    build_frontend

    # Determine which platforms to build
    local platforms_to_build=()
    if [ -z "$target_platform" ]; then
        # Build all platforms
        platforms_to_build=("${PLATFORMS[@]}")
        print_header "Building for All Platforms"
    else
        # Build specific platform
        case "$target_platform" in
            windows)
                platforms_to_build=("windows/amd64/look-alike.exe/look-alike-windows-x64")
                print_header "Building for Windows x64"
                ;;
            darwin-amd64)
                platforms_to_build=("darwin/amd64/look-alike/look-alike-macos-x64")
                print_header "Building for macOS Intel (x64)"
                ;;
            darwin-arm64)
                platforms_to_build=("darwin/arm64/look-alike/look-alike-macos-arm64")
                print_header "Building for macOS Apple Silicon (ARM64)"
                ;;
            *)
                print_msg "$RED" "Unknown platform: $target_platform"
                print_msg "$YELLOW" "Available platforms: windows, darwin-amd64, darwin-arm64"
                exit 1
                ;;
        esac
    fi

    # Build and package each platform
    local success_count=0
    local total_count=${#platforms_to_build[@]}

    for platform_config in "${platforms_to_build[@]}"; do
        IFS='/' read -r goos goarch binary_name archive_name <<< "$platform_config"

        echo ""
        print_msg "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        print_msg "$BLUE" "Building: ${archive_name}"
        print_msg "$BLUE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        # Build backend
        if build_backend "$goos" "$goarch" "$binary_name" "$archive_name"; then
            # Create package
            create_package "$goos" "$goarch" "$binary_name" "$archive_name"
            ((success_count++))
            print_msg "$GREEN" "✓ Successfully packaged ${archive_name}"
        else
            print_msg "$RED" "✗ Failed to build ${archive_name}"
        fi
    done

    # Print summary
    print_header "Packaging Complete"

    if [ $success_count -eq $total_count ]; then
        print_msg "$GREEN" "✓ All packages built successfully ($success_count/$total_count)"
    else
        print_msg "$YELLOW" "⚠ Some packages failed ($success_count/$total_count succeeded)"
    fi

    echo ""
    print_msg "$BLUE" "Output directory: $DIST_DIR/"
    echo ""

    # List generated files
    if [ -d "$DIST_DIR" ]; then
        print_msg "$BLUE" "Generated packages:"
        ls -lh "$DIST_DIR"/*.{zip,tar.gz} 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    fi

    echo ""
}

# Run main function
main "$@"
