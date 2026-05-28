#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$HOME/HAITCH/protocols/HAITCH}"
RUN_NAME="${2:-dwi_run-01}"

find "$ROOT" -type d -name "$RUN_NAME" | while read -r RUN_DIR; do
    echo "========================================"
    echo "Processing run: $RUN_DIR"

    ROI_DIR="$RUN_DIR/ROI"
    mkdir -p "$ROI_DIR"

    cd "$ROI_DIR"

    # subject T2w
    SUB_T2W=$(find . -maxdepth 1 -name "sub-*_T2w.nii.gz" | head -n 1 || true)

    # atlas image + regional label
    ATLAS_IMG=$(find . -maxdepth 1 -name "t2w_GA*_atlas.nii.gz" | head -n 1 || true)
    ATLAS_REGIONAL=$(find . -maxdepth 1 -name "t2w_GA*_regional.nii.gz" | head -n 1 || true)

    if [[ -z "${SUB_T2W:-}" ]]; then
        echo "[WARN] No subject T2w found in $ROI_DIR, skipping."
        continue
    fi

    if [[ -z "${ATLAS_IMG:-}" ]]; then
        echo "[WARN] No atlas image found in $ROI_DIR, skipping."
        continue
    fi

    if [[ -z "${ATLAS_REGIONAL:-}" ]]; then
        echo "[WARN] No atlas regional label found in $ROI_DIR, skipping."
        continue
    fi

    # derive prefix from atlas filename, e.g. t2w_GA35_atlas.nii.gz -> GA35_to_subT2w_
    ATLAS_BASE=$(basename "$ATLAS_IMG")
    GA_TAG=$(echo "$ATLAS_BASE" | sed -E 's/^t2w_(GA[0-9]+)_atlas\.nii\.gz/\1/')
    OUT_PREFIX="${GA_TAG}_to_subT2w_"

    echo "Subject T2w    : $SUB_T2W"
    echo "Atlas image    : $ATLAS_IMG"
    echo "Atlas regional : $ATLAS_REGIONAL"
    echo "Output prefix  : $OUT_PREFIX"

    # Atlas -> subject T2w
    antsRegistrationSyNQuick.sh \
      -d 3 \
      -f "$SUB_T2W" \
      -m "$ATLAS_IMG" \
      -o "$OUT_PREFIX" \
      -t s

    # Apply atlas regional label -> subject T2w
    antsApplyTransforms \
      -d 3 \
      -i "$ATLAS_REGIONAL" \
      -r "$SUB_T2W" \
      -o "t2w_${GA_TAG}_regional_in_subT2w.nii.gz" \
      -n NearestNeighbor \
      -t "${OUT_PREFIX}1Warp.nii.gz" \
      -t "${OUT_PREFIX}0GenericAffine.mat"

    echo "[OK] Finished atlas -> T2w and regional propagation for $RUN_DIR"
done

echo "Done."