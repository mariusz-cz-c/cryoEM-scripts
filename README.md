# cryoEM-scripts

## mrc2png 
This script converts all *.mrc images present in current directory into downsampled png images that are written into png/ subdirectory.

**mrc2png** needs to source include/functions.sh script; it requires EMAN2 software (e2proc2d.py) and 'convert' tool from Imagemagick package.

**IMPORTANT:** This script runs multiple copies of e2proc2d.py / convert commands in parallel and by default it uses 16 threads. If you plan to run it on machine with smaller number of cores/threads (or use more threads in parallel), please modify the value of `max_threads` variable defined at the beginning of this script.

## tif2mrc
This script converts all *.tif images present in current directory into mrc files. It creates 3 output directories: Micrographs/ directory with mrc images that can be imported directly into RELION pipeline; png/ directory with downsampled png images; and tif/ directory, where original tif images are moved.

**tif2mrc** needs to source include/functions.sh script; it requires EMAN2 software (e2proc2d.py) and 'convert' tool from Imagemagick package.

**IMPORTANT:** This script runs multiple copies of e2proc2d.py / convert commands in parallel and by default it uses 16 threads. If you plan to run it on machine with smaller number of cores/threads (or use more threads in parallel), please modify the value of `max_threads` variable defined at the beginning of this script.



## rln_find_movies.sh
This script can be used to collect all movies from EPU session into single Movies subdirectory. Run it inside RELION's project directory - it will make *Movies* subdirectory and create symbolic links to all movies found in provided EPU session path subdirectories.

Usage:
```
rln_find_movies.sh path_to_movies [Movies]
```
where: 
 * *path_to_movies* - **full** path to folder with EPU session, e.g.: `/media/workspaceHDD/190129-KRIOS/supervisor_20190128_151058`
 * *Movies* - **(optional)** subfolder for storing movies (default: Movies)
 
 
## rln_monitor_progress.sh ##
This script prints progress of Class2D, Class3D or Refine3D job from RELION. Run it inside RELION's project directory with job number as an argument, e.g.:
```
rln_monitor_progress.sh 006
```

**rln_monitor_progress.sh** requires gnuplot for printing graphs.

## rln_gctf_local.sh ##
Wrapper script for Gctf to calculate local defocus values for particles from Extract or Polish job inside RELION's project directory. After calculation of local defocus values it uses modified version of star_replace_UVA.com by Kai Zhang to create new star file with local UVA values.

**rln_gctf_local.sh** requires Gctf configured for RELION (as $RELION_GCTF_EXECUTABLE environmental variable) and gnuplot + Ghostscript for printing pdf report with graphs.
