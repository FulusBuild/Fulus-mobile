#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.9}"
FLUTTER_DIR="${HOME}/flutter"
FLUTTER_ARCHIVE="/tmp/flutter.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# Vercel build containers may extract Flutter under a different ownership context.
# Mark the SDK checkout as trusted before invoking Flutter's git-based version checks.
git config --global --add safe.directory "${FLUTTER_DIR}" || true

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "Installing Flutter ${FLUTTER_VERSION}..."
  rm -rf "${FLUTTER_DIR}"
  curl -fsSL --retry 3 "${FLUTTER_URL}" -o "${FLUTTER_ARCHIVE}"
  tar -xf "${FLUTTER_ARCHIVE}" -C "${HOME}"
  rm -f "${FLUTTER_ARCHIVE}"
  git config --global --add safe.directory "${FLUTTER_DIR}" || true
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"
flutter --version
flutter config --no-analytics
flutter pub get
flutter build web -t lib/main_web.dart --release
