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

    # Required files
    SUB_T2W=$(find . -maxdepth 1 -name "sub-*_T2w.nii.gz" | head -n 1 || true)
    DWI_B0=$(find . -maxdepth 1 \( \
  -name "spred*_meanb0.nii.gz" -o \
  -name "spred*_masked_b0.nii.gz" -o \
  -name "spred_b0_masked.nii.gz" \
\) | head -n 1 || true)
    T2W_REGIONAL=$(find . -maxdepth 1 -name "t2w_GA*_regional_in_subT2w.nii.gz" | head -n 1 || true)

    if [[ -z "${SUB_T2W:-}" ]]; then
        echo "[WARN] No subject T2w found in $ROI_DIR, skipping."
        continue
    fi

    if [[ -z "${DWI_B0:-}" ]]; then
        echo "[WARN] No DWI mean b0 found in $ROI_DIR, skipping."
        continue
    fi

    if [[ -z "${T2W_REGIONAL:-}" ]]; then
        echo "[WARN] No T2w-space regional label found in $ROI_DIR, skipping."
        continue
    fi

    echo "Subject T2w   : $SUB_T2W"
    echo "DWI mean b0   : $DWI_B0"
    echo "T2w regional  : $T2W_REGIONAL"

    # Nonlinear refinement: DWI mean b0 -> subject T2w
    antsRegistrationSyNQuick.sh \
      -d 3 \
      -f "$SUB_T2W" \
      -m "$DWI_B0" \
      -o b0_to_T2w_ \
      -t s

    # Bring T2w regional labels back to native DWI space
    GA_TAG=$(basename "$T2W_REGIONAL" | sed -E 's/^t2w_(GA[0-9]+)_regional_in_subT2w\.nii\.gz/\1/')
    OUT_LABEL="t2w_${GA_TAG}_regional_in_DWI.nii.gz"

    antsApplyTransforms \
      -d 3 \
      -i "$T2W_REGIONAL" \
      -r "$DWI_B0" \
      -o "$OUT_LABEL" \
      -n NearestNeighbor \
      -t [b0_to_T2w_0GenericAffine.mat,1] \
      -t b0_to_T2w_1InverseWarp.nii.gz

    echo "[OK] Finished nonlinear refinement and propagated labels back to DWI for $RUN_DIR"
done

echo "Done."
