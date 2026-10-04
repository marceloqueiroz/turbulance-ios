#!/bin/zsh
# Converts any PNG left in the map's asset catalog to HEIC (quality 85, alpha kept) and points its Contents.json at it.
# Map art is soft and painterly, so HEIC is ~10x smaller than PNG with no visible change (2026-10-04: 29 MB -> 3 MB).
# Masters stay as PNG in branding/map/cut/. Run after copying new map pieces into Assets.xcassets/Map.
cd "${0:A:h}/../Turbulence/Assets.xcassets/Map" || exit 1
for d in *.imageset; do
  n=${d%.imageset}
  [ -f "${d:?}/${n:?}.png" ] || continue
  sips -s format heic -s formatOptions 85 "${d:?}/${n:?}.png" --out "${d:?}/${n:?}.heic" >/dev/null 2>&1 &&
    [ "$(sips -g hasAlpha "${d:?}/${n:?}.heic" | tail -1 | awk '{print $2}')" = "yes" ] &&
    rm "${d:?}/${n:?}.png" &&
    sed -i '' "s/\"${n:?}.png\"/\"${n:?}.heic\"/" "${d:?}/Contents.json" &&
    echo "converted $n" || echo "FAILED $n"
done
