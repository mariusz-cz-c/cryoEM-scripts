#!/bin/bash
# This script will locate all movies in predefined subdirectories and create symlinks in Movies or other defined folder for RELION.
# WARNING: It will also delete the '_fractions' part of the filenames.
# Mariusz Czarnocki-Cieciura, 	31.01.2019
# last modification: 		20.01.2020

echo "+------------------------------------------------------------------------------+"
echo "| script created by Mariusz Czarnocki-Cieciura, 31.01.2019                     |"
echo "| last modification: 20.01.2019                                                |"
echo "+------------------------------------------------------------------------------+"

####################################################################################################
### 01. check arguments                                                                          ###
####################################################################################################

if [ $# -lt 1 ]
then
    echo "Usage: `basename $0` path_to_movies [Movies]"
    echo "where: "
    echo "    path_to_movies is [full] path to folder with session, e.g.:"
    echo "        /media/workspaceHDD/190129-KRIOS/supervisor_20190128_151058"
    echo "    Movies is [optional] local folder for storing movies (default = Movies)"
    exit
fi

####################################################################################################
### 02. parse options and define other default parameters                                        ###
####################################################################################################

path_to_movies=$1								# where movies are stored						
new_path=Movies									# where symlinks should be
today=$(date '+%Y-%m-%d %H:%M:%S')						# time stamp
counter="0"
number_of_tiff_files=$(ls 2>/dev/null -Ubad1 -- $new_path/*.tiff | wc -l)	# number of tiff files already present
number_of_mrcs_files=$(ls 2>/dev/null -Ubad1 -- $new_path/*.mrcs | wc -l)	# number of mrc files already present
number_of_files=$((number_of_tiff_files+number_of_mrcs_files))			# number of all movies already present
total_number_of_files=$number_of_files						# total number of files

if [ "$2" != "" ]; then	new_path=$2; fi; 
echo "  selected options:"
echo "  path to movies: $path_to_movies"
echo "  local folder:   $new_path (with $number_of_files tiff/mrcs files)"
if [ ! -d $path_to_movies ]; then 
    echo "ERROR: folder $path_to_movies doesn't exist, quitting..."
    exit
fi
if [ ! -d $new_path ]; then mkdir $new_path; fi; 			# create directory for Micrographs/movies
logfile=$new_path/names.log						# log with all short and long names

####################################################################################################
### 03. process files                                                                            ###
####################################################################################################

shopt -s nullglob							# ignore empty folders
echo "list of all symlinks generated on $today" >> $logfile
echo "+------------------------------------------------------------------------------+"
echo -ne "  initial number of files: $number_of_files, processing file $counter -> total files: $total_number_of_files\r"
for directory in $(find $path_to_movies* -maxdepth 6 -type d); do	# list all subdirectories, depth 4
    lastdir=${directory:(-4)}						# get last 4 characters from directory string
    if [ "$lastdir" == "Data" ]; then					# we are in directory with data
	# check for mrc movies (TODO: WARNING: in EPU version that I was using (2.5) K3 movies are written as _fractions.tiff files, but this might be changed in the future)
        for f in "$directory"/*_fractions.tiff; do 				# select all *tiff files
#	    filesize=$(stat -c%s "$f")					# uncoment this (and corresponding 'fi') to process only files larger than 100 MB
#            if [ "$filesize" -gt "100000000" ]; then 			
                full_filename=$(basename "$f")				# full filename
                filename="${full_filename%_fractions.tiff}.tiff"	# replace "_fractions" from filename
		if [ ! -e $new_path/$filename ]; then
                    ((counter++))
		    total_number_of_files=$((number_of_files + counter))
                    echo -ne "  initial number of files: $number_of_files, processing file $counter -> total files: $total_number_of_files\r"
                    echo "$f -> $new_path/$full_filename" >> $logfile	# full list of filenames
                    ln -s $f $new_path/${filename}
		fi
#            fi
        done
	# check for mrc movies (TODO WARNING: in EPU version that I was using (2.4?) Falcon movies are written as _Fractions.mrc files, but this might be changed in the future)
        for f in "$directory"/*_Fractions.mrc; do 				# select all *tiff files
#	    filesize=$(stat -c%s "$f")					# uncoment this (and corresponding 'fi') to process only files larger than 100 MB
#            if [ "$filesize" -gt "100000000" ]; then 			
                full_filename=$(basename "$f")				# full filename
                filename="${full_filename%_Fractions.mrc}.mrcs"	# replace "_fractions" from filename
		if [ ! -e $new_path/$filename ]; then
                    ((counter++))
		    total_number_of_files=$((number_of_files + counter))
                    echo -ne "  initial number of files: $number_of_files, processing file $counter -> total files: $total_number_of_files\r"
                    echo "$f -> $new_path/$full_filename" >> $logfile	# full list of filenames
                    ln -s $f $new_path/${filename}
		fi
#            fi
        done

    fi
done

echo -e "\n  done processing - $counter files added"
