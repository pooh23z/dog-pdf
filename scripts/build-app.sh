#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DISPLAY_NAME="Dog PDF"
BUNDLE_ID="com.personal.dogpdf"
BUNDLE_DIR="${ROOT_DIR}/dist/${APP_DISPLAY_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="${ROOT_DIR}/assets/AppIconSource.jpg"

cd "${ROOT_DIR}"

echo "▶ Building release binary..."
swift build -c release --product MacWheel
BIN_PATH="$(swift build -c release --show-bin-path)/MacWheel"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Error: built binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "▶ Assembling ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}" "${ROOT_DIR}/dist/โปรเเกรมฉันเอง.app"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/MacWheel"
chmod +x "${MACOS_DIR}/MacWheel"

if [[ -f "${ROOT_DIR}/scripts/setup-deps.sh" ]]; then
  cp "${ROOT_DIR}/scripts/setup-deps.sh" "${RESOURCES_DIR}/setup-deps.sh"
  chmod +x "${RESOURCES_DIR}/setup-deps.sh"
fi

# Generate squircle-masked 1024x1024 macOS AppIcon.icns from our puppy + PDF artwork
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"
BASE_PNG="$(dirname "${ICONSET_DIR}")/icon_1024.png"

swift - "${ICON_SOURCE}" "${BASE_PNG}" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let srcPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// Standard Apple macOS icon inset (~100px transparent padding around 824x824 rounded square)
let inset: CGFloat = 100
let iconRect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let squircle = CGPath(roundedRect: iconRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.25))
ctx.addPath(squircle)
ctx.setFillColor(CGColor.white)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

if let srcURL = URL(fileURLWithPath: srcPath) as CFURL?,
   let imgSource = CGImageSourceCreateWithURL(srcURL, nil),
   let cgSrc = CGImageSourceCreateImageAtIndex(imgSource, 0, nil) {
    ctx.interpolationQuality = .high
    ctx.draw(cgSrc, in: iconRect)
} else {
    let colors = [
        CGColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0),
        CGColor(red: 0.99, green: 0.87, blue: 0.72, alpha: 1.0)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
}

ctx.restoreGState()

// Subtle inner glass highlight border
ctx.addPath(squircle)
ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.45))
ctx.setLineWidth(4)
ctx.strokePath()

guard let outImg = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, outImg, nil)
CGImageDestinationFinalize(dest)
SWIFT

for px in 16 32 128 256 512; do
  sips -z ${px} ${px} "${BASE_PNG}" --out "${ICONSET_DIR}/icon_${px}x${px}.png" >/dev/null
  px2=$((px * 2))
  sips -z ${px2} ${px2} "${BASE_PNG}" --out "${ICONSET_DIR}/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
rm -rf "$(dirname "${ICONSET_DIR}")"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>th</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>MacWheel</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "▶ Ad-hoc code signing bundle..."
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "✅ Built: ${BUNDLE_DIR}"
