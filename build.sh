#!/usr/bin/env bash
# Build a local MOS plugin .deb for MSEdit (host architecture).
# The msedit binary is embedded in the .deb and installed under /usr/lib/msedit.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${1:-${VERSION:-}}"
if [ -z "$VERSION" ]; then
  VERSION="$(node -e "import('./page/plugin.config.js').then(m => console.log(m.default.version))" 2>/dev/null || echo 0.2.0)"
fi

case "$(uname -m)" in
  x86_64|amd64) DEB_ARCH=amd64; MSEDIT_ARCH=x86_64 ;;
  aarch64|arm64) DEB_ARCH=arm64; MSEDIT_ARCH=aarch64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

PKG_NAME="msedit-${VERSION}-1+mos-plugin_${DEB_ARCH}"
PKG_DIR="$ROOT/build/${PKG_NAME}"
DEB_FILE="$ROOT/build/${PKG_NAME}.deb"
PAGE_DIST="$ROOT/page/dist/msedit"
SUFFIX="-${MSEDIT_ARCH}-linux-gnu.tar.gz"

echo "==> MSEdit MOS plugin ${VERSION} (${DEB_ARCH})"

if [ "${SKIP_PAGE:-0}" != "1" ]; then
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required to build the plugin page" >&2
    exit 1
  fi
  if [ ! -d "$ROOT/page/node_modules" ]; then
    echo "==> npm install"
    ( cd "$ROOT/page" && npm install )
  fi
  echo "==> building plugin page"
  ( cd "$ROOT/page" && PLUGIN_VERSION="$VERSION" npm run build )
fi

if [ ! -f "$PAGE_DIST/remoteEntry.js" ]; then
  echo "page build output missing: $PAGE_DIST/remoteEntry.js" >&2
  exit 1
fi

rm -rf "$PKG_DIR"
mkdir -p \
  "$PKG_DIR/DEBIAN" \
  "$PKG_DIR/usr/bin/plugins" \
  "$PKG_DIR/usr/lib/msedit" \
  "$PKG_DIR/usr/share/msedit-plugin" \
  "$PKG_DIR/var/www/mos-plugins/msedit"

echo "==> fetching MSEdit ${SUFFIX}"
REL="$(curl -fsSL --retry 2 https://api.github.com/repos/microsoft/edit/releases/latest)"
TAG="$(printf '%s' "$REL" | jq -r '.tag_name // empty')"
MSEDIT_VERSION="${TAG#v}"
[ -n "$MSEDIT_VERSION" ] || { echo "cannot read MSEdit release" >&2; exit 1; }
URL="$(printf '%s' "$REL" | jq -r --arg s "$SUFFIX" '.assets[] | select(.name | endswith($s)) | .browser_download_url' | head -n1)"
DIGEST="$(printf '%s' "$REL" | jq -r --arg s "$SUFFIX" '.assets[] | select(.name | endswith($s)) | .digest // empty' | head -n1)"
[ -n "$URL" ] || { echo "no Linux asset for $MSEDIT_ARCH" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL --retry 2 "$URL" -o "$TMP/msedit.tar.gz"
if [ -n "$DIGEST" ]; then
  case "$DIGEST" in sha256:*) DIGEST="${DIGEST#sha256:}" ;; esac
  printf '%s  %s\n' "$DIGEST" "$TMP/msedit.tar.gz" | sha256sum -c - >/dev/null
fi
tar -xzf "$TMP/msedit.tar.gz" -C "$TMP"
[ -x "$TMP/edit" ] || { echo "archive does not contain edit" >&2; exit 1; }
install -m 0755 "$TMP/edit" "$PKG_DIR/usr/lib/msedit/msedit"

install -m 0755 "$ROOT/msedit-backend" "$PKG_DIR/usr/bin/plugins/msedit"
install -m 0755 "$ROOT/msedit-wrapper" "$PKG_DIR/usr/bin/msedit"

install -m 0755 "$ROOT/msedit-backend" "$PKG_DIR/usr/share/msedit-plugin/msedit-backend"
install -m 0755 "$ROOT/msedit-wrapper" "$PKG_DIR/usr/share/msedit-plugin/msedit-wrapper"
install -m 0755 "$ROOT/functions" "$PKG_DIR/usr/share/msedit-plugin/functions"
install -m 0644 "$ROOT/settings.json" "$PKG_DIR/usr/share/msedit-plugin/settings.json"

cp -a "$PAGE_DIST/." "$PKG_DIR/var/www/mos-plugins/msedit/"
install -m 0644 "$ROOT/images/msedit.png" "$PKG_DIR/var/www/mos-plugins/msedit/icon.png"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: msedit-plugin
Version: ${VERSION}-1+mos-plugin
Architecture: ${DEB_ARCH}
Maintainer: hustyanzu
Section: utils
Priority: optional
Description: MSEdit plugin for MOS
 Simple terminal text editor inspired by the MS-DOS Editor.
EOF

cat > "$PKG_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
set -e
PLG=/boot/optional/plugins/msedit
SHARE=/usr/share/msedit-plugin
mkdir -p "$PLG/lib" "$PLG/packages"
chmod 0755 /usr/bin/plugins/msedit /usr/bin/msedit 2>/dev/null || true
for f in msedit-backend msedit-wrapper functions; do
  cp -f "$SHARE/$f" "$PLG/$f"
done
chmod 0755 "$PLG/msedit-backend" "$PLG/msedit-wrapper" "$PLG/functions" 2>/dev/null || true
if [ ! -f "$PLG/settings.json" ]; then
  cp -f "$SHARE/settings.json" "$PLG/settings.json"
fi
if [ ! -f "$PLG/packages/packages" ]; then
  pkg="$(apt-cache search '^libicu[0-9]+$' 2>/dev/null | awk '{print $1}' | sort -V | tail -n1)"
  [ -n "$pkg" ] || pkg=libicu76
  printf '%s\n' "$pkg" > "$PLG/packages/packages"
fi
if [ ! -e /usr/bin/edit ]; then
  ln -sf msedit /usr/bin/edit
fi
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postinst"

cat > "$PKG_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/bash
if [ -L /usr/bin/edit ] && [ "$(readlink /usr/bin/edit)" = "msedit" ]; then
  rm -f /usr/bin/edit
fi
exit 0
EOF
chmod 0755 "$PKG_DIR/DEBIAN/postrm"

echo "==> building ${DEB_FILE}"
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB_FILE"
else
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  printf '2.0\n' > "$WORK/debian-binary"
  ( cd "$PKG_DIR/DEBIAN" && tar --owner=0 --group=0 --numeric-owner -czf "$WORK/control.tar.gz" . )
  ( cd "$PKG_DIR" && tar --owner=0 --group=0 --numeric-owner --exclude=./DEBIAN -czf "$WORK/data.tar.gz" . )
  ( cd "$WORK" && ar rcs "$DEB_FILE" debian-binary control.tar.gz data.tar.gz )
fi

md5sum "$DEB_FILE" | awk '{print $1}' > "$DEB_FILE.md5"

echo
echo "Package: $DEB_FILE"
echo "MD5:     $(cat "$DEB_FILE.md5")"
echo "MSEdit:  $MSEDIT_VERSION"
echo
echo "Install the plugin via MOS Hub."