#!/bin/sh
# Construit Transcrire.app sur le Bureau. À relancer après chaque modification des fichiers .swift.
set -e
cd "$(dirname "$0")"
APP=~/Desktop/Transcrire.app
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1. vérifie le moteur (découpage en phrases, timecodes, exports)
swiftc -parse-as-library Moteur.swift verifier.swift -o "$TMP/verifier"
"$TMP/verifier"

# 2. compile l'app
swiftc -O -parse-as-library Transcrire.swift Moteur.swift -o "$TMP/Transcrire"

# 3. dessine l'icône dans toutes les tailles
swiftc icone.swift -o "$TMP/icone"
"$TMP/icone" "$TMP/icone.png"
mkdir "$TMP/AppIcon.iconset"
for t in 16 32 128 256 512; do
  sips -z $t $t "$TMP/icone.png" --out "$TMP/AppIcon.iconset/icon_${t}x${t}.png" >/dev/null
  sips -z $((t * 2)) $((t * 2)) "$TMP/icone.png" --out "$TMP/AppIcon.iconset/icon_${t}x${t}@2x.png" >/dev/null
done

# 4. assemble le paquet .app
pkill -x Transcrire || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/fr.lproj"
mv "$TMP/Transcrire" "$APP/Contents/MacOS/"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Transcrire</string>
  <key>CFBundleDisplayName</key><string>Transcrire</string>
  <key>CFBundleIdentifier</key><string>local.transcrire</string>
  <key>CFBundleExecutable</key><string>Transcrire</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>fr</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Audio ou vidéo</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <!-- Alternate : apparaît dans « Ouvrir avec », sans devenir l'app par défaut des fichiers audio -->
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key><array><string>public.audiovisual-content</string></array>
    </dict>
  </array>
</dict>
</plist>
EOF
xattr -cr "$APP"  # sinon codesign refuse (« detritus not allowed »)
codesign --force --sign - "$APP"
touch "$APP"  # le Finder rafraîchit l'icône
echo "Transcrire.app est prête sur le Bureau."
