#!/usr/bin/env bash
set -euo pipefail

MODEL_SIZE="${1:-medium}"
MODELS_DIR="${HOME}/Library/Application Support/MacWheel/Models"
mkdir -p "${MODELS_DIR}"

echo "=== ตั้งค่าเครื่องมือออฟไลน์สำหรับ Dog PDF ==="

if ! command -v brew >/dev/null 2>&1; then
  echo "❌ ไม่พบ Homebrew ในเครื่อง กรุณาติดตั้งจาก https://brew.sh ก่อน"
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "▶ กำลังติดตั้ง whisper.cpp (สำหรับถอดเสียงออฟไลน์)..."
  brew install whisper-cpp
else
  echo "✅ พบ whisper-cli แล้ว: $(command -v whisper-cli)"
fi

if [[ "${MODEL_SIZE}" == "--small" || "${MODEL_SIZE}" == "small" ]]; then
  MODEL_FILE="ggml-small.bin"
else
  MODEL_FILE="ggml-medium.bin"
fi

MODEL_PATH="${MODELS_DIR}/${MODEL_FILE}"
if [[ -f "${MODEL_PATH}" ]]; then
  echo "✅ พบไฟล์โมเดลแล้ว: ${MODEL_PATH}"
else
  URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_FILE}"
  echo "▶ กำลังดาวน์โหลดโมเดล ${MODEL_FILE} ลงเครื่อง (ครั้งเดียวเท่านั้น)..."
  curl -L --fail --progress-bar "${URL}" -o "${MODEL_PATH}.tmp"
  mv "${MODEL_PATH}.tmp" "${MODEL_PATH}"
  echo "✅ ดาวน์โหลดโมเดลเสร็จสมบูรณ์: ${MODEL_PATH}"
fi

echo ""
echo "🎉 พร้อมใช้งานถอดเสียงออฟไลน์ (ไทย/อังกฤษ) 100% แล้ว! กด 'รีเฟรชสถานะ' ใน Menu Bar ได้เลย"
