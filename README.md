# cryoEM-scripts

## mrc2png 
This script converts all *.mrc images present in current directory into downsampled png images that are written into png/ subdirectory.

**mrc2png** needs to source include/functions.sh script; it requires EMAN2 software (e2proc2d.py) and 'convert' tool from Imagemagick package.

**IMPORTANT:** This script runs multiple copies of e2proc2d.py / convert commands in parallel and by default it uses 16 threads. If you plan to run it on machine with smaller number of cores/threads (or use more threads in parallel), please modify the value of `max_threads` variable defined at the beginning of this script.

## rln_find_movies
This script can be used to collect all movies from EPU session into single Movies subdirectory. Run it inside RELION's project directory - it will make *Movies* subdirectory and create symbolic links to all movies found in provided EPU session path subdirectories.

Usage:
```
rln_find_movies path_to_movies [Movies]
```
where: 
 * *path_to_movies* - **full** path to folder with EPU session, e.g.: `/media/workspaceHDD/190129-KRIOS/supervisor_20190128_151058`
 * *Movies* - **(optional)** subfolder for storing movies (default: Movies)
 
 
