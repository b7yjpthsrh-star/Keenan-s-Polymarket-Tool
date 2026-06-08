#!/usr/bin/env bash
# =============================================================================
#  build.sh — final working version
#  Builds in /tmp to escape iCloud Drive's file-provider daemon
# =============================================================================
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
APP_NAME="PolymarketTool"
DMG_NAME="PolymarketTool-v1.0"
VENV_PATH="$HOME/polymarket-tool-env"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Use a fixed simple name — no $ PID expansion needed, no special chars
STAGING_DIR="/tmp/pm-tool-build"
FINAL_APP="$STAGING_DIR/dist/${APP_NAME}.app"

echo "══════════════════════════════════════════════════════"
echo "  Polymarket Tool — macOS App Builder"
echo "  Project : $PROJECT_DIR"
echo "  Staging : $STAGING_DIR"
echo "══════════════════════════════════════════════════════"
echo ""

# ── 1. Activate venv ──────────────────────────────────────────────────────────
echo "▶  Activating virtual environment…"
source "$VENV_PATH/bin/activate"

# ── 2. Create clean staging area in /tmp ─────────────────────────────────────
echo "▶  Creating clean staging area in /tmp…"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

rsync -a \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.DS_Store' \
    --exclude='build' \
    --exclude='dist' \
    "$PROJECT_DIR/" "$STAGING_DIR/"

# Strip any xattrs rsync carried over from the source
xattr -cr "$STAGING_DIR"
echo "   ✅  Staging area ready and clean"

# ── 3. Run PyInstaller from inside the staging dir ───────────────────────────
echo "▶  Running PyInstaller…"
cd "$STAGING_DIR"

pyinstaller build.spec \
    --noconfirm \
    --clean \
    --distpath "$STAGING_DIR/dist" \
    --workpath "$STAGING_DIR/build"

# ── 4. Verify bundle ──────────────────────────────────────────────────────────
echo ""
echo "▶  Verifying .app bundle exists…"
if [ ! -d "$FINAL_APP" ]; then
    echo "❌  Build failed — .app not found at: $FINAL_APP"
    exit 1
fi
echo "   ✅  .app bundle found"

# ── 5. Strip ALL extended attributes ─────────────────────────────────────────
# Run twice: once immediately, once after a short pause to catch any
# late-writing daemon. In /tmp there are no iCloud daemons, so this
# is purely a belt-and-suspenders measure.
echo "▶  Stripping extended attributes (pass 1)…"
xattr -cr "$FINAL_APP"
find "$FINAL_APP" -name ".DS_Store" -delete 2>/dev/null || true
find "$FINAL_APP" -name "._*"       -delete 2>/dev/null || true

sleep 1

echo "▶  Stripping extended attributes (pass 2)…"
xattr -cr "$FINAL_APP"
find "$FINAL_APP" -name ".DS_Store" -delete 2>/dev/null || true
find "$FINAL_APP" -name "._*"       -delete 2>/dev/null || true

# ── 6. Remove specific known-problem attributes file-by-file ─────────────────
# NOTE: attribute names with # must be quoted carefully; we use a helper
# function to avoid any quoting/parsing issue in the while-loop.
echo "▶  Removing known-persistent attributes on every file…"

strip_one_file() {
    local f="$1"
    xattr -d com.apple.FinderInfo            "$f" 2>/dev/null || true
    xattr -d com.apple.quarantine            "$f" 2>/dev/null || true
    # The fileprovider attr name contains # — pass it as a variable
    local FPATTR="com.apple.fileprovider.fpfs#P"
    xattr -d "$FPATTR"                       "$f" 2>/dev/null || true
}
export -f strip_one_file

# xargs with -P4 runs 4 parallel workers — faster on large bundles
find "$FINAL_APP" -print0 \
    | xargs -0 -P4 -I{} bash -c 'strip_one_file "$@"' _ {}

# ── 7. Final confirmation ─────────────────────────────────────────────────────
echo "▶  Confirming no xattrs remain…"
REMAINING=$(xattr -r "$FINAL_APP" 2>/dev/null || true)
if [ -n "$REMAINING" ]; then
    echo "   Attributes still present:"
    echo "$REMAINING" | sed 's/^/     /'
    echo ""
    echo "   ⚠  Attempting one more nuclear strip…"
    xattr -cr "$FINAL_APP"
    REMAINING2=$(xattr -r "$FINAL_APP" 2>/dev/null || true)
    if [ -n "$REMAINING2" ]; then
        echo "   ❌  Could not fully strip. Proceeding anyway — sign may still work."
    else
        echo "   ✅  Clean after second pass"
    fi
else
    echo "   ✅  Bundle is clean"
fi

# ── 8. Ad-hoc sign — inside-out ──────────────────────────────────────────────
echo "▶  Signing internal frameworks…"
if [ -d "$FINAL_APP/Contents/Frameworks" ]; then
    find "$FINAL_APP/Contents/Frameworks" \
        \( -name "*.dylib" -o -name "*.so" \) -print0 2>/dev/null \
      | xargs -0 -P4 -I{} codesign --force --sign - "{}" 2>/dev/null || true
fi

echo "▶  Signing MacOS binaries…"
if [ -d "$FINAL_APP/Contents/MacOS" ]; then
    find "$FINAL_APP/Contents/MacOS" -type f -print0 2>/dev/null \
      | xargs -0 -P4 -I{} codesign --force --sign - "{}" 2>/dev/null || true
fi

echo "▶  Signing top-level bundle…"
codesign \
    --force \
    --deep \
    --sign - \
    "$FINAL_APP"

# ── 9. Verify signature ───────────────────────────────────────────────────────
echo "▶  Verifying signature…"
if codesign --verify --deep --strict "$FINAL_APP" 2>&1; then
    echo "   ✅  Signature valid"
else
    echo "   ⚠   Ad-hoc signature applied (Gatekeeper prompt expected — normal)"
fi

# ── 10. Copy back to project ──────────────────────────────────────────────────
echo "▶  Copying signed .app to project dist/…"
mkdir -p "$PROJECT_DIR/dist"
rm -rf "$PROJECT_DIR/dist/${APP_NAME}.app"
ditto "$FINAL_APP" "$PROJECT_DIR/dist/${APP_NAME}.app"
# Strip anything ditto may have pulled from the destination filesystem
xattr -cr "$PROJECT_DIR/dist/${APP_NAME}.app" 2>/dev/null || true

# ── 11. DMG ───────────────────────────────────────────────────────────────────
cd "$PROJECT_DIR"

echo "▶  Installing create-dmg if needed…"
if ! command -v create-dmg &>/dev/null; then
    brew install create-dmg
fi

xattr -cr dist/ 2>/dev/null || true

echo "▶  Building DMG…"
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "${APP_NAME}.app" 175 190 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 425 190 \
    "dist/${DMG_NAME}.dmg" \
    "dist/${APP_NAME}.app" \
    || true

# ── 12. Cleanup ───────────────────────────────────────────────────────────────
echo "▶  Cleaning up staging area…"
rm -rf "$STAGING_DIR"

# ── 13. Report ────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
if [ -f "dist/${DMG_NAME}.dmg" ]; then
    SIZE=$(du -sh "dist/${DMG_NAME}.dmg" | cut -f1)
    echo "  ✅  BUILD COMPLETE"
    echo ""
    echo "  App  : dist/${APP_NAME}.app"
    echo "  DMG  : dist/${DMG_NAME}.dmg   ($SIZE)  ← send this"
else
    ditto -c -k --keepParent \
        "dist/${APP_NAME}.app" \
        "dist/${APP_NAME}.zip"
    SIZE=$(du -sh "dist/${APP_NAME}.zip" | cut -f1)
    echo "  ✅  BUILD COMPLETE (zip fallback)"
    echo ""
    echo "  App  : dist/${APP_NAME}.app"
    echo "  ZIP  : dist/${APP_NAME}.zip   ($SIZE)  ← send this"
fi
echo ""
echo "  Friend opens it:"
echo "  → Right-click the .app → Open → click Open"
echo "══════════════════════════════════════════════════════"
