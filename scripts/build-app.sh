#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DISPLAY_NAME="โปรเเกรมฉันเอง"
BUNDLE_DIR="${ROOT_DIR}/dist/${APP_DISPLAY_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

cd "${ROOT_DIR}"

echo "▶ Building release binary..."
swift build -c release --product MacWheel
BIN_PATH="$(swift build -c release --show-bin-path)/MacWheel"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Error: built binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "▶ Assembling ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/MacWheel"
chmod +x "${MACOS_DIR}/MacWheel"

if [[ -f "${ROOT_DIR}/scripts/setup-deps.sh" ]]; then
  cp "${ROOT_DIR}/scripts/setup-deps.sh" "${RESOURCES_DIR}/setup-deps.sh"
  chmod +x "${RESOURCES_DIR}/setup-deps.sh"
fi

# Generate a crisp Tangerine-wheel macOS .icns icon programmatically
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"
BASE_PNG="$(dirname "${ICONSET_DIR}")/icon_1024.png"

swift - "${BASE_PNG}" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments[1]
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

let rect = CGRect(x: 40, y: 40, width: 944, height: 944)
let bgPath = CGPath(roundedRect: rect, cornerWidth: 220, cornerHeight: 220, transform: nil)
ctx.addPath(bgPath)
ctx.clip()

let colors = [
    CGColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0),
    CGColor(red: 0.99, green: 0.87, blue: 0.72, alpha: 1.0)
] as CFArray
if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
    ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 984), end: CGPoint(x: 512, y: 40), options: [])
}

let center = CGPoint(x: 512, y: 512)
let outerR: CGFloat = 340
let innerR: CGFloat = 115
let sliceColors: [CGColor] = [
    CGColor(red: 0.98, green: 0.45, blue: 0.12, alpha: 1.0),
    CGColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1.0),
    CGColor(red: 0.93, green: 0.30, blue: 0.38, alpha: 1.0),
    CGColor(red: 0.22, green: 0.56, blue: 0.96, alpha: 1.0),
    CGColor(red: 0.16, green: 0.74, blue: 0.62, alpha: 1.0),
    CGColor(red: 0.58, green: 0.42, blue: 0.94, alpha: 1.0)
]

for i in 0..<6 {
    let start = CGFloat(i) * (.pi / 3.0) + 0.04
    let end = CGFloat(i + 1) * (.pi / 3.0) - 0.04
    ctx.beginPath()
    ctx.addArc(center: center, radius: outerR, startAngle: start, endAngle: end, clockwise: false)
    ctx.addArc(center: center, radius: innerR, startAngle: end, endAngle: start, clockwise: true)
    ctx.closePath()
    ctx.setFillColor(sliceColors[i])
    ctx.fillPath()
}

ctx.setFillColor(CGColor.white)
ctx.fillEllipse(in: CGRect(x: center.x - innerR + 10, y: center.y - innerR + 10, width: (innerR - 10) * 2, height: (innerR - 10) * 2))
ctx.setFillColor(CGColor(red: 0.95, green: 0.42, blue: 0.12, alpha: 1.0))
ctx.fillEllipse(in: CGRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84))

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, img, nil)
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
    <string>com.personal.macwheel</string>
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
