#!/usr/bin/env bash
set -euo pipefail

#
# Build a self-contained Redash bundle for offline WSL/UBI9 deployment
#
# Usage:
#   ./build_redash_bundle.sh
#
# Environment variables:
#   REDASH_GIT_URL  - Git URL to clone (default: https://github.com/getredash/redash.git)
#   REDASH_REF      - Git tag/branch/commit (default: v25.8.0)
#   OUT_TGZ         - Output tarball name (default: redash-bundle-<ref>.tgz)
#   PYTHON_VERSION  - Python version to use (default: python3.10)
#

# ---- Configuration ----
REDASH_GIT_URL="${REDASH_GIT_URL:-https://github.com/getredash/redash.git}"
REDASH_REF="${REDASH_REF:-v25.8.0}"
PYTHON_VERSION="${PYTHON_VERSION:-python3.10}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sanitize ref for filename (replace / with -)
REF_SAFE="${REDASH_REF//\//-}"
OUT_TGZ="${OUT_TGZ:-redash-bundle-${REF_SAFE}.tgz}"

# ---- Working directories ----
WORKDIR="$(mktemp -d)"
SRC_DIR="$WORKDIR/redash"
BUNDLE_DIR="$WORKDIR/bundle"
WHEEL_DIR="$BUNDLE_DIR/wheels"
APP_DIR="$BUNDLE_DIR/app"

cleanup() {
  echo "Cleaning up..."
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "============================================"
echo "Redash Bundle Builder"
echo "============================================"
echo "Source:  $REDASH_GIT_URL"
echo "Ref:     $REDASH_REF"
echo "Python:  $PYTHON_VERSION"
echo "Output:  $OUT_TGZ"
echo "============================================"
echo

# ---- Step 1: Clone Redash ----
echo "[1/6] Cloning Redash ($REDASH_REF)..."
git clone --depth 1 --branch "$REDASH_REF" "$REDASH_GIT_URL" "$SRC_DIR"
echo

# ---- Step 2: Build frontend ----
echo "[2/6] Building frontend assets..."
cd "$SRC_DIR"

# Check for node/yarn
if ! command -v node &> /dev/null; then
  echo "ERROR: node is required but not found"
  exit 1
fi
if ! command -v yarn &> /dev/null; then
  echo "ERROR: yarn is required but not found"
  exit 1
fi

export NODE_OPTIONS="--openssl-legacy-provider"

# Use network-concurrency 1 to avoid cache corruption in containers
# Don't set NODE_ENV=production during install (need devDependencies for build)
yarn install --network-concurrency 1

# Now build with production mode
NODE_ENV=production yarn build
echo

# ---- Step 3: Export Python dependencies and build wheels ----
echo "[3/6] Building Python wheelhouse..."

# Check for poetry (install 1.x if not present - 2.x has compatibility issues)
if ! command -v poetry &> /dev/null; then
  echo "  Installing Poetry 1.8.x..."
  pip install "poetry>=1.8,<2.0" --quiet
fi

# Export requirements from poetry
cd "$SRC_DIR"
poetry export -f requirements.txt -o requirements.txt --without-hashes

# Create venv for building wheels
"$PYTHON_VERSION" -m venv "$WORKDIR/venv"
source "$WORKDIR/venv/bin/activate"
python -m pip install --upgrade pip wheel setuptools

mkdir -p "$WHEEL_DIR"

# Download all wheels
echo "  Downloading wheels..."
python -m pip download -r requirements.txt -d "$WHEEL_DIR"

# Verify wheels were downloaded
WHEEL_COUNT=$(find "$WHEEL_DIR" -name "*.whl" | wc -l)
echo "  Downloaded $WHEEL_COUNT wheel files"

if [[ "$WHEEL_COUNT" -eq 0 ]]; then
  echo "ERROR: No wheels were downloaded!"
  exit 1
fi

# Build wheels for any sdists (so target doesn't need to compile)
SDISTS=$(find "$WHEEL_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.zip" \) 2>/dev/null || true)
if [[ -n "${SDISTS}" ]]; then
  echo "  Building wheels from source distributions..."
  python -m pip wheel -r requirements.txt -w "$WHEEL_DIR"
  # Remove sdists, keep only wheels
  rm -f "$WHEEL_DIR"/*.tar.gz "$WHEEL_DIR"/*.zip 2>/dev/null || true
fi

deactivate
echo

# ---- Step 4: Assemble bundle ----
echo "[4/6] Assembling bundle..."
mkdir -p "$APP_DIR"

# Copy Redash source (excluding unnecessary files)
rsync -a \
  --exclude ".git" \
  --exclude "node_modules" \
  --exclude ".pytest_cache" \
  --exclude "__pycache__" \
  --exclude "*.pyc" \
  --exclude ".venv" \
  --exclude "tests" \
  --exclude ".github" \
  --exclude ".ci" \
  "$SRC_DIR/" "$APP_DIR/"

# Copy requirements.txt to app dir
cp "$SRC_DIR/requirements.txt" "$APP_DIR/"

# Copy launcher scripts from templates
cp -r "$SCRIPT_DIR/bundle-templates/bin" "$BUNDLE_DIR/"
chmod +x "$BUNDLE_DIR/bin/"*

# Copy env template
cp "$SCRIPT_DIR/bundle-templates/redash.env.example" "$BUNDLE_DIR/"
echo

# ---- Step 5: Create tarball ----
echo "[5/6] Creating tarball..."
tar -C "$BUNDLE_DIR" -czf "$SCRIPT_DIR/$OUT_TGZ" .
echo

# ---- Step 6: Done ----
echo "[6/6] Done!"
echo
echo "Bundle created: $SCRIPT_DIR/$OUT_TGZ"
echo
echo "To deploy:"
echo "  1. Copy $OUT_TGZ to target system"
echo "  2. Extract: mkdir redash && tar -xzf $OUT_TGZ -C redash"
echo "  3. Configure: cp redash.env.example redash.env && nano redash.env"
echo "  4. Initialize DB: ./bin/init_db"
echo "  5. Start services:"
echo "     ./bin/server    # Web server"
echo "     ./bin/worker    # Background jobs"
echo "     ./bin/scheduler # Scheduled tasks"
