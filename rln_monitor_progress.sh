#!/bin/bash
# Mariusz Czarnocki-Cieciura, 	17.12.2018
# last modification: 		23.02.2020


echo "+------------------------------------------------------------------------------+"
echo "| script created by Mariusz Czarnocki-Cieciura, 17.12.2018,                    |"
echo "| last modification: 23.02.2030                                                |"
echo "+------------------------------------------------------------------------------+"

####################################################################################################
### 01. Important variables and functions used in this script                                    ###
####################################################################################################

job_nr=""				# job number (provided as the first argument of this script)
job_dir=""				# job directory (determined based on the user input)
job_type=""				# job type (determined based on the user input)
last_filename=""			# name of (specific) file for last iteratio
number_of_files=""			# number of files (iterations) present in job directory
last_iteration=""			# last iteration (string)
prefix=""				# filename prefix 		(defined after last_iteration)
orientations_output=""			# .dat file with orientations 	(defined after last_iteration)
offsets_output=""			# .dat file with offsets 	(defined after last_iteration)
classes_output=""			# .dat file with classes 	(defined after last_iteration)
resolution_output=""			# .dat file with resolution	(defined after last_iteration)
gnuplot_script=""			# .plt file with gnuplot sript	(defined after last_iteration)
gnuplot_graph=""			# svg file with gnuplot graph 	(defined after last_iteration)
process=false				# process files, create dat files and svg graph
final_resolution=""			# final resolution calculated from run.out file


# this function will grep for value in $1 in optimiser.star files and print it to file $2
grep_values(){
    local search_pattern=$1				# $1 -> search pattern
    local output_file="$job_dir/$2"			# $2 -> output filename
    # first search for standard rounds -> files run_it???_optimiser.star
    grep $search_pattern $job_dir/run_it???_optimiser.star | \
	sed -e 's/_optimiser.star:'$search_pattern'//' | sed -e "s+${job_dir}/run_++" | \
	awk '{print "run_" $1 "\t" $2}' > $output_file
    # next check 'continue' dounds -> files run_ct_it???_optimiser.star
    if ls $job_dir/run_ct* 1> /dev/null 2>&1; then
        grep $search_pattern $job_dir/run_ct*it???_optimiser.star | \
	    sed -e 's/_optimiser.star:'$search_pattern'//' | sed -e "s+${job_dir}/run_++" | \
            awk '{print $1 "\t" $2}' >> $output_file
    fi
}

# this function will grep for resolution in run.out file and print it to file $1
grep_resolution(){
    local output_file="$job_dir/$1"			# $2 -> output filename
    grep "Auto-refine: Resolution" $job_dir/run.out | sed -e 's/ Auto-refine: Resolution= //' | \
	awk '{printf("it%03d\t%12.6f\n", NR-1, $1)}' > $output_file
}

# this function will grep for final resolution in run.out file and print it to stdout
grep_final_resolution(){
    grep "Final resolution (" $job_dir/run.out | sed -e 's/ Auto-refine: + //'
}

# this function conuts particles in each class using awk/gawk
count_in_class(){
    local data_filename=$1						# $1 -> last run_*_data.star file
    local model_filename=${1%_data.star}_model.star			# last run_*_model.star file
    if [ ! -f $data_filename ]; then					# check if file exists
        echo "ERROR: file $data_filename doesn't exist, quitting..."
        exit
    fi
    if [ ! -f $model_filename ]; then					# check if file exists
        echo "ERROR: file $model_filename doesn't exist, quitting..."
        exit
    fi

    # parse model.star and data_star files and find positions of headers etc
    start_here=$(awk 'NR<50 && /data_model_classes/{print NR}'	$model_filename)
    end_here=$(awk 'NR<5000 && /data_model_class_1/{print NR; exit}'	$model_filename)
    rlnReferenceImage=$(awk 'NR<50 && /rlnReferenceImage/{print $2}'	$model_filename | cut -c 2-)
    rlnClassDistribution=$(awk 'NR<50 && /rlnClassDistribution/{print $2}'	$model_filename | cut -c 2-)
    rlnEstimatedResolution=$(awk 'NR<50 && /rlnEstimatedResolution/{print $2}'	$model_filename | cut -c 2-)
    rlnClassNumber=$(awk 'NR<50 && /rlnClassNumber/{print $2}'	$data_filename | cut -c 2-)

    # process both files
    gawk 'BEGIN{}/mrc/{								# read only lines with 'mrc' 
        if(FILENAME==ARGV[1]){							# 1. preprocess model_file
            if (NR>='$start_here' && NR<'$end_here'){	 			  # read only lines in this range
		class++;							  # start from 1
		n_particles[class] = 0;						  # initialize array with zeros
		distribution[class] = $'$rlnClassDistribution';			  # add value to array 
		resolution[class] = $'$rlnEstimatedResolution'; 		  # add value to array 

	    }}
	    if(FILENAME==ARGV[2]){						# 2. preprocess data_file
		total_particles++;						  # count all particles
		n_particles[$'$rlnClassNumber']++;}				  # count particles in class
	}END{
	    print "particles    [%]    class   resolution";			# print header
            for (key in n_particles) { 						# loop through all records and prepare text
		text=sprintf("%7d %8.2f%% %6d %12s\n", n_particles[key], distribution[key]*100, key, resolution[key]);
		values[key]=text}
	    k = asort(values, values_sorted)					# sort records according to the number of particles
	    for (i = k; i >= 1; i--) {						# print records
		printf("%s", values_sorted[i])}
	    print "\ntotal number of particles: "total_particles;			# print header
	}'   $model_filename   $data_filename #>> $new_starfile
}

####################################################################################################
### 02. Parse arguments                                                                          ###
####################################################################################################

if [ $# -ne 1 ]
then
	echo "Usage: `basename $0` XXX"
	echo "where XXX is Class2D, Class3D or Refine3D job number."
	echo "This script must be executed in Relion's project directory."
	echo "You can selected from one of the following jobs:"
	ls -ld 2>/dev/null Class*/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'
	ls -ld 2>/dev/null Refine*/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'
	exit
fi

job_nr=$1
job_dir="$(find */job* -maxdepth 0 -type d | grep job$job_nr)"
job_type=$(echo $job_dir | cut -d'/' -f 1)

if [ "$job_type" == "" ]; then
	echo "couldn't find job nuber $job_nr..."
	exit
fi

echo "job directory = $job_dir; job type = $job_type"
echo ""

if [ "$job_type" != "Class2D" -a "$job_type" != "Refine3D" -a "$job_type" != "Class3D" ]; then
	echo "job type $job_type is not proper job for this script..."
	exit
fi


####################################################################################################
### 03. Check if script was already executed in provided job directory                           ###
####################################################################################################

# count iterations
search_for="$job_dir/run*optimiser.star"
number_of_files=$(ls 2>/dev/null -Ubad1 -- $search_for | wc -l)
if [ $number_of_files -gt "1" ]; then 
    process=true
else
    echo "ERROR: only $number_of_files optimiser.star file present in $job_dir - nothing to do here..."
    exit
fi

# find last iteration
search_for="$job_dir/run_it*optimiser.star"
if ls $job_dir/run_ct* 1> /dev/null 2>&1; then
    search_for="$job_dir/run_ct*optimiser.star"
fi

for FILE in `find $search_for -type f`
do
    last_filename=$FILE
done

last_iteration=$(echo "${last_filename##*/}" | sed -e 's/run_//; s/_optimiser.star//')

# define filenames
prefix="rln_monitor_progress_job${job_nr}_${last_iteration}"
orientations_output="${prefix}_orientations.dat"			# .dat file with orientations
offsets_output="${prefix}_offsets.dat"					# .dat file with offsets
classes_output="${prefix}_classes.dat"					# .dat file with classes
resolution_output="${prefix}_resolution.dat"				# .dat file with resolution
gnuplot_script="${prefix}_gnu.plt"					# .plt file with gnuplot sript
gnuplot_graph="${prefix}_graph.svg"					# svg file with graph generated by gnuplot

# check if graph is present and backup all files if necessary
if [ -f $job_dir/$gnuplot_graph ]; then
    echo "WARNING: output svg file already exists!"
    echo "It seems that this script was already executed for this iteration..."
    read -p ' -> do you want to override created files? [y/n]: ' yn
    case $yn in
        [yY][eE][sS]|[yY]) 						# backup previous results
	    mv $job_dir/$orientations_output 	$job_dir/${orientations_output}.bak 	> /dev/null 2>&1 
	    mv $job_dir/$offsets_output 	$job_dir/${offsets_output}.bak 		> /dev/null 2>&1 
	    mv $job_dir/$classes_output		$job_dir/${classes_output}.bak 		> /dev/null 2>&1
	    mv $job_dir/$resolution_output	$job_dir/${resolution_output}.bak	> /dev/null 2>&1  
	    mv $job_dir/$gnuplot_script		$job_dir/${gnuplot_script}.bak		> /dev/null 2>&1 
	    mv $job_dir/$gnuplot_graph 		$job_dir/${gnuplot_graph}.bak 		> /dev/null 2>&1 
	    ;;
        *) 
	    process=false						# don't process files, just list them
	    ;;
    esac
    echo ""
fi

####################################################################################################
### 04. Process all *.optimiser.star files and run.out file                                      ###
####################################################################################################

if [ $process = true ] ; then

    grep_values 	"_rlnChangesOptimalOrientations"	"$orientations_output"
    grep_values 	"_rlnChangesOptimalOffsets" 		"$offsets_output"

    if [ $job_type == "Refine3D" ] ; then
        grep_resolution 					"$resolution_output"
    else							# Class2D or Class3D
        grep_values 	"_rlnChangesOptimalClasses" 		"$classes_output"
    fi
fi

if [ $job_type == "Refine3D" ] ; then
    final_resolution=$(grep_final_resolution)
    final_resolution=${final_resolution:-"Final resolution not determined yet..."} # substr
fi

####################################################################################################
### 05. Print table with numerical results                                                       ###
####################################################################################################

if [ $job_type == "Refine3D" ] ; then
    echo -e "iteration\torientations\toffsets   \tresolution"
    paste $job_dir/$orientations_output $job_dir/$offsets_output $job_dir/$resolution_output | \
	awk '{print $1 "\t" $2 "\t" $4 "\t" $6}'
    echo -e "\n$final_resolution\n"
else
    echo -e "iteration\torientations\toffsets   \tclasses"
    paste $job_dir/$orientations_output $job_dir/$offsets_output $job_dir/$classes_output | awk '{print $1 "\t" $2 "\t" $4 "\t" $6}'
    echo ""
fi

####################################################################################################
### 06. Prepare and run gnuplot script                                                           ###
####################################################################################################
if [ $process = true ]; then
    echo "reset
do for [IDX = 0:1] {
  if (IDX==1) {
    set terminal svg noenhanced
    set output '$gnuplot_graph'
  }
  unset xtic
  set key autotitle columnhead
  set tmargin 0
  set bmargin 2
  set lmargin 5
  set rmargin 2
  set multiplot
  set size 1.0,0.3
  set origin 0.0,0.68" > $job_dir/$gnuplot_script
        if [ $job_type == "Refine3D" ] ; then
	    echo "  plot [][] '$resolution_output' using 2:xtic(1) with lines title \"resolution\"" >> $job_dir/$gnuplot_script
	else		# Class2D or Class3D
	    echo "  plot [][0:1] '$classes_output' using 2:xtic(1) with lines title \"classes\"" >> $job_dir/$gnuplot_script
	fi
	echo "  set size 1.0,0.3
  set origin 0.0,0.38
  plot [][] '$offsets_output' using 2:xtic(1) with lines title 'offsets'
  set xtic rotate nomirror noenhanced
  set size 1.0,0.3
  set origin 0.0,0.08
  plot [][] '$orientations_output' using 2:xtic(1) with lines title 'orientations'
  unset multiplot
}" >> $job_dir/$gnuplot_script
fi

# and plot all the graphs
(cd $job_dir/ ; gnuplot -persist $gnuplot_script)


####################################################################################################
### 07. Open images with relion_display                                                          ###
####################################################################################################

# define search parameters
if [ $job_type == "Refine3D" ] ; then
    search_for="$job_dir/run_it*1_class001.mrc"
    if ls $job_dir/run_ct* 1> /dev/null 2>&1; then
        search_for="$job_dir/run_ct*1_class001.mrc"
    fi
else		# Class2D or Class3D
    search_for="$job_dir/run_it*_model.star"
    if ls $job_dir/run_ct* 1> /dev/null 2>&1; then
        search_for="$job_dir/run_ct*_model.star"
    fi
fi

# find most recent file
for FILE in `find $search_for -type f`
do
    last_filename=$FILE
done

relion_display --i $last_filename --gui > /dev/null 2>&1 & 

####################################################################################################
### 08. Print classes                                                                            ###
####################################################################################################

# print classes IF results are from Class2D/Class3D
if [ $job_type != "Refine3D" ] ; then

    search_for="$job_dir/run_it*_data.star"
    if ls $job_dir/run_ct* 1> /dev/null 2>&1; then
        search_for="$job_dir/run_ct*_data.star"
    fi

    for FILE in `find $search_for -type f`
    do
        last_filename=$FILE
    done

    count_in_class $last_filename
fi

