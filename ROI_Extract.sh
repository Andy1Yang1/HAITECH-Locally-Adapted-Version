#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$HOME/HAITCH/protocols/HAITCH}"
RUN_NAME="${2:-dwi_run-01}"

# Label IDs from T2WAtlas_labelkey-region.txt
IFGoper_L_ID=11
IFGoper_R_ID=12
IFGtri_L_ID=13
IFGtri_R_ID=14
SupraMarginal_L_ID=63
SupraMarginal_R_ID=64
Temporal_Sup_L_ID=81
Temporal_Sup_R_ID=82

extract_roi () {
    local infile="$1"
    local label_id="$2"
    local outfile="$3"
    mrcalc "$infile" "$label_id" -eq "$outfile" -force
}

find "$ROOT" -type d -name "$RUN_NAME" | while read -r RUN_DIR; do
    echo "----------------------------------------"
    echo "Processing run: $RUN_DIR"

    ROI_DIR="$RUN_DIR/ROI"
    MASK_DIR="$ROI_DIR/masks"

    # Create ROI folder if missing
    mkdir -p "$ROI_DIR"
    mkdir -p "$MASK_DIR"

    # First try ROI folder
    REGIONAL_FILE=$(find "$ROI_DIR" -maxdepth 1 -name "t2w_GA*_regional_in_DWI.nii.gz" | head -n 1 || true)

    # If not found, try run root
    if [[ -z "${REGIONAL_FILE:-}" ]]; then
        REGIONAL_FILE=$(find "$RUN_DIR" -maxdepth 1 -name "t2w_GA*_regional_in_DWI.nii.gz" | head -n 1 || true)
    fi

    if [[ -z "${REGIONAL_FILE:-}" ]]; then
        echo "[WARN] No regional_in_DWI file found in $RUN_DIR, skipping."
        continue
    fi

    echo "Using: $(basename "$REGIONAL_FILE")"

    # AF ROI
    extract_roi "$REGIONAL_FILE" "$IFGtri_L_ID"       "$MASK_DIR/IFGtri_L.nii.gz"
    extract_roi "$REGIONAL_FILE" "$IFGtri_R_ID"       "$MASK_DIR/IFGtri_R.nii.gz"
    extract_roi "$REGIONAL_FILE" "$Temporal_Sup_L_ID" "$MASK_DIR/Temporal_Sup_L.nii.gz"
    extract_roi "$REGIONAL_FILE" "$Temporal_Sup_R_ID" "$MASK_DIR/Temporal_Sup_R.nii.gz"

    # SLF ROI
    extract_roi "$REGIONAL_FILE" "$IFGoper_L_ID"       "$MASK_DIR/IFGoper_L.nii.gz"
    extract_roi "$REGIONAL_FILE" "$IFGoper_R_ID"       "$MASK_DIR/IFGoper_R.nii.gz"
    extract_roi "$REGIONAL_FILE" "$SupraMarginal_L_ID" "$MASK_DIR/SupraMarginal_L.nii.gz"
    extract_roi "$REGIONAL_FILE" "$SupraMarginal_R_ID" "$MASK_DIR/SupraMarginal_R.nii.gz"

    echo "[OK] Saved AF/SLF ROI masks to $MASK_DIR"
done

echo "Done."