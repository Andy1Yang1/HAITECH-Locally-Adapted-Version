# HAITCH-Locally-Adapted-Version
Local workflow scripts and configuration for HAITECH 

Note: Please do not use step 9-10, downstream analysis were separately performed outside of HAITCH, so Steps 9–10 are disabled in the provided step-control config.

Data Organization:

HAITCH/data/sub-*/ses-*/dwi/run-*

Data Naming:
sub-XXX_ses-YY_dwi_run-ZZ.nii.gz
sub-XXX_ses-YY_dwi_run-ZZ.bvals
sub-XXX_ses-YY_dwi_run-ZZ.bvecs
Sub-XXX_ses-YY_dwi_run-ZZ_info.json
Data Naming example:
sub-XXX_ses-01_dwi_run-01.nii.gz
sub-XXX_ses-01_dwi_run-01.bvals
sub-XXX_ses-01_dwi_run-01.bvecs
sub-XXX_ses-01_dwi_run-01_info.json

1.Run the prerequisite script first, which generates the corresponding  _grad_mrtrix.txt and the acqparams.txt needed before running the bash. 
Then run the batch HAITCH script.

Single Subject Example:
bash prerequisite_files.sh ~/HAITCH sub-XXX

All subject Example: 
bash prerequisite_files.sh ~/HAITCH

2.Then run the batch HAITCH script

Sinelg Subject Example:
bash run_batch_haitch.sh \
. \
./dMRI_HAITCH_Fixed.sh \
./user_config_steps1_8.sh \
sub-XXX \
2>&1 | tee batch_run_sub-XXX.log

All Subject Example:
bash run_batch_haitch.sh \
. \
./dMRI_HAITCH_Fixed.sh \
./user_config_steps1_8.sh \
2>&1 | tee batch_run_all.log
