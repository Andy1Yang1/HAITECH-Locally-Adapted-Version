#!/usr/bin/env bash
set -euo pipefail


if [[ $# -lt 3 ]]; then
  echo "======================================================================="
  echo " ERROR: Missing required arguments."
  echo " Usage: bash $0 <PROJECT_DIR> <PIPELINE_SCRIPT> <STEP_CONFIG> [Subjects...]"
  echo ""
  echo " Example (Run ALL subjects in data folder):"
  echo "   bash $0 /path/to/HAITCH /path/to/HAITCH/dMRI_HAITCH_Fixed.sh /path/to/HAITCH/user_config_steps1_8.sh"
  echo "======================================================================="
  exit 1
fi



PROJECT_DIR="$(realpath "$1")"
PIPELINE_SCRIPT="$(realpath "$2")"
STEP_CONFIG="$(realpath "$3")"
shift 3
SUBJECT_FILTER=("$@")

PROJNAME="${PROJNAME:-BCH}"
DWIMODALITY="${DWIMODALITY:-dwi}"
MCMETHOD="${MCMETHOD:-HAITCH}"
MRTRIX_NTHREADS="${MRTRIX_NTHREADS:-24}"
NBATCH="${NBATCH:-8}"
DEVICE="${DEVICE:-gpu}"
BATCH_SIZE="${BATCH_SIZE:-4}"
SEGMENTATION_METHOD="${SEGMENTATION_METHOD:-RAZIEH}"
SING="${SING:-0}"
NOLOCKS="${NOLOCKS:-}"
REGSTRAT="${REGSTRAT:-ants}"
#ACQPARAM_DEFAULT="${PROJECT_DIR}/refs/acq_parameters_dMRI_scan.txt"
#ACQPARAM="${ACQPARAM:-$ACQPARAM_DEFAULT}"
CONFIG_DIR="${PROJECT_DIR}/batch_configs"
mkdir -p "$CONFIG_DIR"

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

build_config() {
  local subj="$1"
  local ses="$2"
  local run="$3"
  local run_dir="$4"
  local cfg="$5"
  local base="${subj}_${ses}_dwi_${run}"

  cat > "$cfg" <<CFG
#!/usr/bin/env bash
set -e
export PROJNAME="$PROJNAME"
export SUBJECTID="$subj"
export DWIMODALITY="$DWIMODALITY"
export DWISESSION="$ses"
export RUNNUM="$run"
export MCMETHOD="$MCMETHOD"
export FULLSUBJECTID="${base}"
export PROJDIR="$PROJECT_DIR"
export DMRISCRIPTS="$PROJECT_DIR"
export SRC="\${DMRISCRIPTS}/src"
export REFS="\${DMRISCRIPTS}/refs"
export TMPDIR="\${PROJDIR}/tmp"
export INPATH="\${PROJDIR}/data"
export OUTPATH="\${PROJDIR}/protocols"
export INPATHSUB="$run_dir"
export OUTPATHSUB="\${OUTPATH}/HAITCH/${subj}/${ses}/dwi_${run}"
export REGSTRAT="$REGSTRAT"
export NOLOCKS="$NOLOCKS"
export BVALS="${run_dir}/${base}.bvals"
export BVECS="${run_dir}/${base}.bvecs"
export BVALSTE="${run_dir}/${base}_TE.bvals"
export BVECSTE="${run_dir}/${base}_TE.bvecs"
export GRAD4CLS="${run_dir}/${base}_grad_mrtrix.txt"
export GRAD4CLSTE="${run_dir}/${base}_grad_mrtrix_TE.txt"
export GRAD5CLS="${run_dir}/${base}_grad5cls_mrtrix.txt"
export INDX="${run_dir}/${base}_index_mrtrix.txt"
export JSONF="${run_dir}/${base}_info.json"
export ACQPARAM="${PROJECT_DIR}/refs/${base}_acqparams.txt"
export T2W_DATA="\${T2W_DATA:-\${PROJDIR}/protocols/t2w}"
export dstripe_docker_image="maxpietsch/dstripe:1.1"
export NBATCH="$NBATCH"
export MRTRIX_NTHREADS="$MRTRIX_NTHREADS"
export device="$DEVICE"
export batch_size="$BATCH_SIZE"
export SEGMENTATION_METHOD="$SEGMENTATION_METHOD"
export SING="$SING"
CFG
  chmod +x "$cfg"
}

check_required_inputs() {
  local subj="$1"
  local ses="$2"
  local run="$3"
  local run_dir="$4"
  local base="${subj}_${ses}_dwi_${run}"
  local acqp_file="${PROJECT_DIR}/refs/${base}_acqparams.txt"
  local fail=0
  local nii

  nii="$(find_input_nii "$run_dir")"
  if [[ -z "$nii" ]]; then
    echo "[SKIP] ${subj} ${ses} ${run}: no input DWI NIfTI found in $run_dir"
    return 1
  fi

  for f in \
    "${run_dir}/${base}.bvals" \
    "${run_dir}/${base}.bvecs" \
    "${run_dir}/${base}_grad_mrtrix.txt" \
    "${run_dir}/${base}_info.json" \
    "$acqp_file"; do
    if [[ ! -f "$f" ]]; then
      echo "[MISSING] $f"
      fail=1
    fi
  done

  if [[ $fail -ne 0 ]]; then
    echo "[SKIP] ${subj} ${ses} ${run}: missing required inputs"
    return 1
  fi
  return 0
}


if [[ ! -f "$PIPELINE_SCRIPT" ]]; then
  echo "Pipeline script not found: $PIPELINE_SCRIPT"
  exit 1
fi
if [[ ! -f "$STEP_CONFIG" ]]; then
  echo "Step config not found: $STEP_CONFIG"
  exit 1
fi

echo "PROJECT_DIR   = $PROJECT_DIR"
echo "PIPELINE      = $PIPELINE_SCRIPT"
echo "STEP_CONFIG   = $STEP_CONFIG"
echo "ACQPARAM      = per-run refs/\${subj}_\${ses}_dwi_\${run}_acqparams.txt"
echo "CONFIG_DIR    = $CONFIG_DIR"

action_count=0
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

  if ! check_required_inputs "$subj" "$ses" "$run" "$run_dir"; then
    continue
  fi

  cfg="$CONFIG_DIR/${subj}_${ses}_${run}_config.sh"
  build_config "$subj" "$ses" "$run" "$run_dir" "$cfg"

  echo "--------------------------------------------------------------------------------"
  echo "[RUN] $subj $ses $run"
  echo "      config = $cfg"
  USER_CONFIG_PATH="$STEP_CONFIG" bash "$PIPELINE_SCRIPT" "$cfg"
  action_count=$((action_count + 1))
done < <(find "$PROJECT_DIR/data" -type d -path '*/ses-*/dwi/run-*' | sort)

echo "--------------------------------------------------------------------------------"
echo "Finished. Launched $action_count run(s)."
