#!/usr/bin/env bash
set -euo pipefail

# Batch tractography pipeline for AF/SLF ROI-to-ROI tracking
# Usage:
#   ./batch_AF_SLF_tractography.sh
#   ./batch_AF_SLF_tractography.sh ~/HAITCH/protocols/HAITCH dwi_run-01
#
# Assumptions:
# - Each subject has .../<dwi_run>/ROI/
# - DWI-space AF/SLF ROI masks already exist in ROI/masks/
# - A masked DWI .mif exists in ROI/ (prefer gradcheck version)
# - A brain/tracking mask exists in ROI/ (tracking_mask.nii.gz, spred5mask.nii, etc.)
# - Mean b0 exists in ROI/ for density-map template; otherwise the DWI image is used as template

ROOT="${1:-$HOME/HAITCH/protocols/HAITCH}"
RUN_NAME="${2:-dwi_run-01}"

MAX_SEEDS=1000000
N_SELECT=5000
CUTOFF=0.05
MINLEN=10
MAXLEN=120
THRESH=2

find "$ROOT" -type d -name "$RUN_NAME" | while read -r RUN_DIR; do
    ROI_DIR="$RUN_DIR/ROI"
    [[ -d "$ROI_DIR" ]] || continue

    echo "========================================"
    echo "Processing: $ROI_DIR"
    cd "$ROI_DIR"

    mkdir -p fod_tracts tracks density metrics

    # Prefer gradcheck version if present
    DWI=$(find . -maxdepth 1 -type f \( \
        -name "spred*_masked_gradcheck.mif" -o \
        -name "spred*_masked_gradchecked.mif" -o \
        -name "spred*_masked.mif" \
    \) | sort | head -n 1 || true)

    if [[ -z "${DWI:-}" ]]; then
        echo "[WARN] No suitable DWI .mif found in $ROI_DIR, skipping."
        continue
    fi

# Mean b0 template if available
TEMPLATE=$(find . -maxdepth 1 -type f \( \
    -name "spred*_meanb0.nii.gz" -o \
    -name "spred*_masked_b0.nii.gz" -o \
    -name "spred_b0_masked.nii.gz" \
\) | sort | head -n 1 || true)
    if [[ -z "${TEMPLATE:-}" ]]; then
        TEMPLATE="$DWI"
    fi

    # Optional tracking / brain mask
    # If a proper binary tracking mask exists, use it.
    # Otherwise, do not pass -mask (do NOT use b0 intensity image as a mask).
    TRACK_MASK=$(find . -maxdepth 1 -type f \( \
        -name "tracking_mask.nii.gz" -o \
        -name "tracking_mask.nii" -o \
        -name "spred5mask.nii" -o \
        -name "spred5mask.nii.gz" \
    \) | sort | head -n 1 || true)

    # ROI masks
    REQUIRED_ROIS=(
        "masks/IFGtri_L.nii.gz"
        "masks/IFGtri_R.nii.gz"
        "masks/Temporal_Sup_L.nii.gz"
        "masks/Temporal_Sup_R.nii.gz"
        "masks/IFGoper_L.nii.gz"
        "masks/IFGoper_R.nii.gz"
        "masks/SupraMarginal_L.nii.gz"
        "masks/SupraMarginal_R.nii.gz"
    )

    MISSING=0
    for roi in "${REQUIRED_ROIS[@]}"; do
        if [[ ! -f "$roi" ]]; then
            echo "[WARN] Missing ROI: $roi"
            MISSING=1
        fi
    done
    if [[ "$MISSING" -ne 0 ]]; then
        echo "[WARN] Missing required ROIs in $ROI_DIR, skipping."
        continue
    fi

    echo "DWI         : $DWI"
    echo "Template    : $TEMPLATE"
    if [[ -n "${TRACK_MASK:-}" ]]; then
        echo "Track mask  : $TRACK_MASK"
    else
        echo "Track mask  : <none; using masked DWI without explicit -mask>"
    fi

    # -------------------------
    # Response functions
    # -------------------------
    if [[ -n "${TRACK_MASK:-}" ]]; then
        dwi2response dhollander \
            "$DWI" \
            fod_tracts/wm_response.txt \
            fod_tracts/gm_response.txt \
            fod_tracts/csf_response.txt \
            -mask "$TRACK_MASK" \
            -force
    else
        dwi2response dhollander \
            "$DWI" \
            fod_tracts/wm_response.txt \
            fod_tracts/gm_response.txt \
            fod_tracts/csf_response.txt \
            -force
    fi

    # -------------------------
    # WM/CSF CSD
    # -------------------------
    if [[ -n "${TRACK_MASK:-}" ]]; then
        dwi2fod msmt_csd \
            "$DWI" \
            fod_tracts/wm_response.txt fod_tracts/wmfod_single_shell.mif \
            fod_tracts/csf_response.txt fod_tracts/csffod_single_shell.mif \
            -mask "$TRACK_MASK" \
            -force
    else
        dwi2fod msmt_csd \
            "$DWI" \
            fod_tracts/wm_response.txt fod_tracts/wmfod_single_shell.mif \
            fod_tracts/csf_response.txt fod_tracts/csffod_single_shell.mif \
            -force
    fi

    # -------------------------
    # AF_L
    # -------------------------
    if [[ -n "${TRACK_MASK:-}" ]]; then
        tckgen fod_tracts/wmfod_single_shell.mif tracks/AF_L_final.tck \
            -algorithm iFOD2 \
            -seed_image masks/IFGtri_L.nii.gz \
            -include masks/Temporal_Sup_L.nii.gz \
            -mask "$TRACK_MASK" \
            -seeds "$MAX_SEEDS" \
            -select "$N_SELECT" \
            -cutoff "$CUTOFF" \
            -minlength "$MINLEN" \
            -maxlength "$MAXLEN" \
            -force
    else
        tckgen fod_tracts/wmfod_single_shell.mif tracks/AF_L_final.tck \
            -algorithm iFOD2 \
            -seed_image masks/IFGtri_L.nii.gz \
            -include masks/Temporal_Sup_L.nii.gz \
            -seeds "$MAX_SEEDS" \
            -select "$N_SELECT" \
            -cutoff "$CUTOFF" \
            -minlength "$MINLEN" \
            -maxlength "$MAXLEN" \
            -force
    fi

    # AF_R
    if [[ -n "${TRACK_MASK:-}" ]]; then
        tckgen fod_tracts/wmfod_single_shell.mif tracks/AF_R_final.tck \
            -algorithm iFOD2 \
            -seed_image masks/IFGtri_R.nii.gz \
            -include masks/Temporal_Sup_R.nii.gz \
            -mask "$TRACK_MASK" \
            -seeds "$MAX_SEEDS" \
            -select "$N_SELECT" \
            -cutoff "$CUTOFF" \
            -minlength "$MINLEN" \
            -maxlength "$MAXLEN" \
            -force
    else
        tckgen fod_tracts/wmfod_single_shell.mif tracks/AF_R_final.tck \
            -algorithm iFOD2 \
            -seed_image masks/IFGtri_R.nii.gz \
            -include masks/Temporal_Sup_R.nii.gz \
            -seeds "$MAX_SEEDS" \
            -select "$N_SELECT" \
            -cutoff "$CUTOFF" \
            -minlength "$MINLEN" \
            -maxlength "$MAXLEN" \
            -force
    fi

    # SLF_L
    if [[ -n "${TRACK_MASK:-}" ]]; then
        tckgen fod_tracts/wmfod_single_shell.mif tracks/SLF_L_final.tck \
            -algorithm iFOD2 \
            -seed_image masks/IFGoper_L.nii.gz \
            -include masks/SupraMarginal_L.nii.gz \
            -mask "$TRACK_MASK" \
            -seeds "$MAX_SEEDS" \
            -select "$N_SELECT" \
            -cutoff "$CUTOFF" \
            -minlength "$MINLEN" \
            -maxlength "$MAXLEN" \
            -force
    else
        tckgen fod_tracts/wmfod_single_shell.mif tracks/SLF_L_final.tck \
            -algorithm iFOD2 \
            -seed_image masks/IFGoper_L.nii.gz \
            -include masks/SupraMarginal_L.nii.gz \
            -seeds "$MAX_SEEDS" \
            -select "$N_SELECT" \
            -cutoff "$CUTOFF" \
            -minlength "$MINLEN" \
            -maxlength "$MAXLEN" \
            -force
    fi

    # SLF_R
    if [[ -n "${TRACK_MASK:-}" ]]; then
        tckgen fod_tracts/wmfod_single_shell.mif tracks/SLF_R_final.tck \
            -algorithm iFOD2 \
            -seed_image masks/IFGoper_R.nii.gz \
            -include masks/SupraMarginal_R.nii.gz \
            -mask "$TRACK_MASK" \
            -seeds "$MAX_SEEDS" \
            -select "$N_SELECT" \
            -cutoff "$CUTOFF" \
            -minlength "$MINLEN" \
            -maxlength "$MAXLEN" \
            -force
    else
        tckgen fod_tracts/wmfod_single_shell.mif tracks/SLF_R_final.tck \
            -algorithm iFOD2 \
            -seed_image masks/IFGoper_R.nii.gz \
            -include masks/SupraMarginal_R.nii.gz \
            -seeds "$MAX_SEEDS" \
            -select "$N_SELECT" \
            -cutoff "$CUTOFF" \
            -minlength "$MINLEN" \
            -maxlength "$MAXLEN" \
            -force
    fi

    # -------------------------
    # Density maps
    # -------------------------
    tckmap tracks/AF_L_final.tck density/AF_L_final_dense.nii.gz \
        -template "$TEMPLATE" -precise -force
    tckmap tracks/AF_R_final.tck density/AF_R_final_dense.nii.gz \
        -template "$TEMPLATE" -precise -force
    tckmap tracks/SLF_L_final.tck density/SLF_L_final_dense.nii.gz \
        -template "$TEMPLATE" -precise -force
    tckmap tracks/SLF_R_final.tck density/SLF_R_final_dense.nii.gz \
        -template "$TEMPLATE" -precise -force

    # -------------------------
    # Thresholded tract masks
    # -------------------------
 mrcalc density/AF_L_final_dense.nii.gz "$THRESH" -ge density/AF_L_final_thr${THRESH}_mask.nii.gz -force
    mrcalc density/AF_R_final_dense.nii.gz "$THRESH" -ge density/AF_R_final_thr${THRESH}_mask.nii.gz -force
    mrcalc density/SLF_L_final_dense.nii.gz "$THRESH" -ge density/SLF_L_final_thr${THRESH}_mask.nii.gz -force
    mrcalc density/SLF_R_final_dense.nii.gz "$THRESH" -ge density/SLF_R_final_thr${THRESH}_mask.nii.gz -force

    echo "[OK] Final outputs generated for $ROI_DIR:"
    ls -lh density/*_dense.nii.gz
    ls -lh density/*_thr${THRESH}_mask.nii.gz

echo "Done."
