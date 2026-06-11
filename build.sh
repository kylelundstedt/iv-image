#!/bin/bash
# Build and push the IV custom exe.dev image to a registry.
# Run on an amd64 builder. See README.md for the SemVer convention and gotchas.
set -euxo pipefail
cd "$(dirname "$0")"

EXEUNTU_COMMIT=d20aa680543e4b4364e54bb9a9248cfb787aaa93   # pinned exeuntu base
IV_VERSION=1.8.0                                          # SemVer of the IV overlay
REG=${REG:-localhost:5000}                                # registry to push to
IMG=$REG/iv-image
BASE_TAG=${EXEUNTU_COMMIT:0:12}
MAJOR=${IV_VERSION%%.*}; MINOR=${IV_VERSION%.*}            # 1 ; 1.1

# --- fetch pinned exeuntu source (base build context) ---
if [ ! -d exeuntu/.git ]; then
  git clone https://github.com/boldsoftware/exeuntu.git exeuntu
fi
git -C exeuntu fetch origin
git -C exeuntu checkout -q "$EXEUNTU_COMMIT"

# --- build (amd64 + --network=host required; see README gotchas) ---
echo "=== building exeuntu-base (pinned $BASE_TAG) ==="
docker build --network=host -t "$REG/exeuntu-base:$BASE_TAG" ./exeuntu

echo "=== building iv-image:$IV_VERSION ==="
docker build --network=host --build-arg "BASE=$REG/exeuntu-base:$BASE_TAG" \
  -t "$IMG:$IV_VERSION" -f Dockerfile.iv .

# floating aliases — consumers pin to the precision they want
docker tag "$IMG:$IV_VERSION" "$IMG:$MINOR"     # 1.1 -> latest 1.1.x
docker tag "$IMG:$IV_VERSION" "$IMG:$MAJOR"     # 1   -> latest 1.x

echo "=== pushing ==="
docker push "$REG/exeuntu-base:$BASE_TAG"
for t in "$IV_VERSION" "$MINOR" "$MAJOR"; do docker push "$IMG:$t"; done

echo "=== ALL DONE ==="
# record the immutable manifest digest of the exact build we pushed
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$IMG:$IV_VERSION")
printf '%s  %s\n' "$(date -u +%FT%TZ)" "$DIGEST" >> digests.log
echo "pinnable: $DIGEST"
docker run --rm "$IMG:$IV_VERSION" duckdb --version
