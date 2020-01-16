# cryoEM-scripts

## mrc2png 
This scripts creates converts all mrc images present in current directory into downsampled png images written into png/ subdirectory.

**mrc2png** needs to source include/functions.sh script; it requires EMAN2 software (e2proc2d.py) and 'convert' tool from Imagemagick package.

**IMPORTANT:** This script runs multiple copies of e2proc2d.py / convert commands in parallel and by default it uses 16 threads. If you plan to run it on machine with smaller number of cores/threads (or use more threads in parallel), please modify the value of `max_threads` variable defined at the beginning of this script.

