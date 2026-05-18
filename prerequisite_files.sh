#!/usr/bin/env bash
set -euo pipefail

# Generate per-run prerequisite files for HAITCH batch processing:
#   1) ${base}_grad_mrtrix.txt   -> stored in each run directory
#   2) ${base}_acqparams.txt     -> stored in PROJECT_DIR/refs/
#
# Expected input per run:
#   - *_dwi*.nii.gz
#   - ${base}.bvals
#   - ${base}.bvecs
#   - ${base}_info.json
#
# Usage:
#   bash prerequisite_files.sh <PROJECT_DIR> [Subjects...]
# Optional env vars:
#   FORCE=1                  overwrite existing outputs
#   DEFAULT_TOTAL_READOUT=0.05   fallback if JSON lacks TotalReadoutTime
#   DEFAULT_PEDIR=j-             fallback if JSON lacks PhaseEncodingDirection

if [[ $# -lt 1 ]]; then
  echo "Usage: bash $0 <PROJECT_DIR> [Subjects...]"
  exit 1
fi

PROJECT_DIR="$(realpath "$1")"
shift || true
SUBJECT_FILTER=("$@")
FORCE="${FORCE:-0}"
DEFAULT_TOTAL_READOUT="${DEFAULT_TOTAL_READOUT:-}"
DEFAULT_PEDIR="${DEFAULT_PEDIR:-}"
REFS_DIR="${PROJECT_DIR}/refs"
mkdir -p "$REFS_DIR"

match_subject() {
  local subj="$1"
  if [[ ${#SUBJECT_FILTER[@]} -eq 0 ]]; then
    return 0
  fi
  local item
  for item in "${SUBJECT_FILTER[@]}"; do
    if [[ "$subj" == "$item" ]]; then
      return 0
    fi
  done
  return 1
}

find_input_nii() {
  local run_dir="$1"
  find "$run_dir" -maxdepth 1 -type f \( -name '*_dwi_*.nii.gz' -o -name '*_dwi.nii.gz' \) | sort | head -n 1
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Required command not found: $cmd"
    exit 1
  fi
}

need_cmd python3
need_cmd mrinfo

json_get_acqp() {
  local jsonf="$1"
  python3 - "$jsonf" "$DEFAULT_TOTAL_READOUT" "$DEFAULT_PEDIR" <<'PY'
import json, sys
jsonf, default_trt, default_pedir = sys.argv[1:4]
with open(jsonf, 'r') as f:
    j = json.load(f)

ped = j.get('PhaseEncodingDirection')
if (ped is None or ped == '') and default_pedir:
    ped = default_pedir

trt = j.get('TotalReadoutTime', j.get('EstimatedTotalReadoutTime'))
if (trt is None or trt == '') and default_trt:
    trt = float(default_trt)

mapping = {
    'i':  ( 1,  0,  0),
    'i-': (-1,  0,  0),
    'j':  ( 0,  1,  0),
    'j-': ( 0, -1,  0),
    'k':  ( 0,  0,  1),
    'k-': ( 0,  0, -1),
}

if ped not in mapping:
    raise SystemExit(f"Missing/unsupported PhaseEncodingDirection in {jsonf}: {ped!r}")
if trt is None or trt == '':
    raise SystemExit(f"Missing TotalReadoutTime/EstimatedTotalReadoutTime in {jsonf}")

x, y, z = mapping[ped]
print(f"{x} {y} {z} {float(trt)}")
PY
}

generate_grad_mrtrix() {
  local nii="$1"
  local bvec="$2"
  local bval="$3"
  local out="$4"

  if [[ -f "$out" && "$FORCE" != "1" ]]; then
    echo "[KEEP] $out"
    return 0
  fi

  mrinfo "$nii" -fslgrad "$bvec" "$bval" -export_grad_mrtrix "$out" >/dev/null
  echo "[MAKE] $out"
}

generate_acqp() {
  local jsonf="$1"
  local out="$2"
  local line

  if [[ -f "$out" && "$FORCE" != "1" ]]; then
    echo "[KEEP] $out"
    return 0
  fi

  line="$(json_get_acqp "$jsonf")"
  printf '%s\n' "$line" > "$out"
  echo "[MAKE] $out    ($line)"
}

count_total=0
count_done=0
count_skip=0

while IFS= read -r run_dir; do
  run_dir="$(realpath "$run_dir")"
  run="$(basename "$run_dir")"
  dwi_dir="$(dirname "$run_dir")"
  ses_dir="$(dirname "$dwi_dir")"
  subj_dir="$(dirname "$ses_dir")"
  ses="$(basename "$ses_dir")"
  subj="$(basename "$subj_dir")"

  if ! match_subject "$subj"; then
    continue
  fi

  count_total=$((count_total + 1))
  base="${subj}_${ses}_dwi_${run}"
  nii="$(find_input_nii "$run_dir")"
  bval="${run_dir}/${base}.bvals"
  bvec="${run_dir}/${base}.bvecs"
  jsonf="${run_dir}/${base}_info.json"
  grad_out="${run_dir}/${base}_grad_mrtrix.txt"
  acqp_out="${REFS_DIR}/${base}_acqparams.txt"

  echo "--------------------------------------------------------------------------------"
  echo "[RUN] $subj $ses $run"
  echo "      run_dir = $run_dir"

  missing=0
  if [[ -z "$nii" ]]; then
    echo "[MISSING] DWI NIfTI in $run_dir"
    missing=1
  fi
  for f in "$bval" "$bvec" "$jsonf"; do
    if [[ ! -f "$f" ]]; then
      echo "[MISSING] $f"
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    echo "[SKIP] Required base files missing"
    count_skip=$((count_skip + 1))
    continue
  fi

  generate_grad_mrtrix "$nii" "$bvec" "$bval" "$grad_out"
  generate_acqp "$jsonf" "$acqp_out"
  count_done=$((count_done + 1))

done < <(find "$PROJECT_DIR/data" -type d -path '*/ses-*/dwi/run-*' | sort)

echo "--------------------------------------------------------------------------------"
echo "Done. processed=$count_done skipped=$count_skip discovered=$count_total"
echo "ACQP files are in: $REFS_DIR"
