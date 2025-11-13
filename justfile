# Onkyo Volume Build Automation

# Default recipe - show available commands
default:
    @just --list

# Generate Xcode project from project.yml
generate:
    @echo "Generating Xcode project..."
    xcodegen generate

# Run tests
test: generate
    @echo "Running tests..."
    xcodebuild clean test \
        -scheme OnkyoVolume \
        -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath ./build \
        -enableCodeCoverage YES \
        -only-testing:OnkyoVolumeTests \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGN_STYLE=Automatic \
        | grep -E '(Test Suite|Test Case|executed|passed|failed)' || true
    @echo "✓ Tests complete"

# Build debug configuration
build-debug: generate
    @echo "Building debug configuration..."
    xcodebuild build \
        -scheme OnkyoVolume \
        -configuration Debug \
        -derivedDataPath ./build
    @echo "✓ Debug build complete: ./build/Build/Products/Debug/OnkyoVolume.app"

# Build release configuration
build-release: generate
    @echo "Building release configuration..."
    xcodebuild build \
        -scheme OnkyoVolume \
        -configuration Release \
        -derivedDataPath ./build
    @echo "✓ Release build complete: ./build/Build/Products/Release/OnkyoVolume.app"

# Create DMG package from release build
package-dmg VERSION: build-release
    @echo "Creating DMG for version {{VERSION}}..."
    @mkdir -p ./dist
    create-dmg \
        --volname "Onkyo Volume" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "OnkyoVolume.app" 175 120 \
        --hide-extension "OnkyoVolume.app" \
        --app-drop-link 425 120 \
        "./dist/OnkyoVolume-{{VERSION}}.dmg" \
        "./build/Build/Products/Release/OnkyoVolume.app"
    @echo "✓ DMG created: ./dist/OnkyoVolume-{{VERSION}}.dmg"

# Complete release pipeline
release VERSION:
    @echo "Starting release pipeline for version {{VERSION}}..."
    @just build-release
    @just package-dmg {{VERSION}}
    @echo "✓ Release {{VERSION}} complete!"

# Clean build artifacts
clean:
    @echo "Cleaning build artifacts..."
    rm -rf ./build
    rm -rf ./dist
    @echo "✓ Clean complete"

# Clean everything including generated Xcode project
clean-all: clean
    @echo "Removing generated Xcode project..."
    rm -rf ./OnkyoVolume.xcodeproj
    @echo "✓ Deep clean complete"
