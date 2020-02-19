#!/bin/bash
# Mariusz Czarnocki-Cieciura, 	16.01.2019
# last modification: 		23.12.2019
# it uses part of the script star_replace_UVA.com by Kai Zhang
# http://www.mrc-lmb.cam.ac.uk/kzhang/useful_tools/

echo "+------------------------------------------------------------------------------+"
echo "| script created by Mariusz Czarnocki-Cieciura, 16.01.2019,                    |"
echo "| last modification: 23.12.2019                                                |"
echo "+------------------------------------------------------------------------------+"

####################################################################################################
### 00. Definitions of functions used in this script                                              ###
####################################################################################################

#this function reads user input (FLOAT) with provided querry $1 and  (optional) default value $2
read_input_float(){					#$1 -> text, $2 -> default value
    local text=$1
    local default_value=$2
    if [ "$default_value" = "" ]; then 
        local querry=" -> $1: "
    else
	local querry=" -> $1 [default: $2]: "
    fi
    local value=""
    is_float="^([0-9]*[.])?[0-9]+$"			# for +/- use "^[+-]?([0-9]*[.])?[0-9]+$"
    while [[ ! ${value} =~ $is_float ]]; do
        read -p "$querry" value 
        if [ "$value" = "" ]; then value=$default_value; fi
    done
    echo $value
}

progress_trap(){
    local search_pattern=$1				# $1 -> search pattern inside Micrographs subdirectory
    local MAX_NUMBER=$2					# $2 -> number of files to be processed
    local SKIP_FILES=$3					# $3 -> number of files to be skipped	
    local counter=$(find $output_dir/$subdir -type f ! -empty -name $search_pattern | wc -l)
    counter=$((counter-SKIP_FILES)) 
    local duration=$SECONDS
    local ETA="0"
    local percent=$(bc <<< "scale=2; 100*$counter/$MAX_NUMBER")
    echo -en "\rProcessing Images: [==================================================] "
    echo -en "$percent% ($counter out of $MAX_NUMBER), "
    TZ=UTC0	printf 'time: %(%H:%M:%S)T, ETA: %(%H:%M:%S)T' "$duration" "$ETA"
    exit
}

progress(){						# $1 $2 $3
	local search_pattern=$1				# $1 -> search pattern inside Micrographs subdirectory
	local MAX_NUMBER=$2				# $2 -> number of files to be processed
	local SKIP_FILES=$3				# $3 -> number of files to be skipped
	SECONDS=0					# timer for ETA
	trap "{ progress_trap "$1" "$2" "$3"; }" SIGINT SIGTERM
	while true
	do
		counter=$(find $output_dir/$subdir -type f ! -empty -name $search_pattern | wc -l)		# this counts only non-empty files!
		counter=$((counter-SKIP_FILES)) 
		frac=$((50*counter/MAX_NUMBER))					# int fraction (x/50)
		percent=$(bc <<< "scale=2; 100*$counter/$MAX_NUMBER")		# float percent progress
		duration=$SECONDS
		echo -n "Processing Images: ["
		for ((i=0; i<$frac; i++)); do echo -ne =; done
		for ((i=0; i<$((50-frac)); i++)); do echo -ne -; done
		echo -ne "] $percent% ($counter out of $MAX_NUMBER), "
		if [ "$duration" -gt "0" ] && [ "$counter" != "0" ]; then		#   ETA =  (total-processed) * (duration/processed)
			ETA=$(( (MAX_NUMBER-counter) * duration/counter))
		        TZ=UTC0	printf 'time: %(%H:%M:%S)T, ETA: %(%H:%M:%S)T\r' "$duration" "$ETA"		# print process time
		else
		        TZ=UTC0	printf 'time: %(%H:%M:%S)T\r' "$duration" 					# print process time
		fi
		sleep 2					# TODO 2 seconds migth be too much or too small -> maby define it based on the MAX_NUMBER?
	done
}


wait_gctf_trap(){
    local Gctf_pid=$!
    local thread=$1		# $1 -> current thread
#    trap "{ echo \"SIGINT detected! Quitting Gctf on thread $thread...\"; kill $Gctf_pid; exit 255; }" SIGINT SIGTERM
#    trap "{ echo \"SIGINT detected! Quitting Gctf on thread $thread...\"; kill $Gctf_pid; }" SIGINT SIGTERM
    trap "{ kill $Gctf_pid; }" SIGINT SIGTERM
    wait $Gctf_pid
}

run_gctf(){			# $1 $2
	local full_list=$1	# $1 -> list of images to be processed
	local thread=$2		# $2 -> current thread
	local short_list=""
	local counter="1"
	local current_thread="1"
	local batch_number="1"
	for f in $full_list; do		# split list into batches
		short_list[$batch_number]="${short_list[$batch_number]} $f"
		((counter++))
		if [ "$counter" -gt "$batch_size" ]; then
			counter="1"
			((batch_number++))
		fi
	done
	for f in "${!short_list[@]}"; do 				# loop through keys in this array (!!)
		gctf_command="$Gctf_exe --apix $apix --cs $cs --kv $kv --ac $ac --astm $astm \
				--logsuffix $logsuffix --do_EPA $do_EPA --gid $gid ${short_list[$f]} --do_local_refine $do_local_refine\
				--boxsuffix $boxsuffix --do_validation $do_validation --ctfstar $ctfstar --write_local_ctf $write_local_ctf"

		$gctf_command  >> $output_dir/Gctf_${thread}.log &
		wait_gctf_trap $thread
	done
}


plot_data(){
    local input=$1
    local output_eps=$2
    local title=$3
    local xlabel=$4
    local ylabel=$5
    local columns=$6
    echo "reset
    set terminal postscript eps size 11.69,8.27 noenhanced color font 'Helvetica,20' linewidth 2
    set output '$output_eps'
    stats '$input' using 0 nooutput				# get number of records
    set multiplot
    set size 0.8,0.8
    set origin 0.1,0.1
    set key autotitle columnhead
    set lmargin 5
    set tics scale 0,0
    set bars small	# for some plots
    set grid
    set title '$title'
    set xlabel '$xlabel'
    set ylabel '$ylabel'
    plot [STATS_min:STATS_max-1] '$input' using $columns lc rgb \"red\" lw 2 title \"\"
    unset multiplot
    set output" | gnuplot
}


run_compare(){
    local full_list=$1					# $1 -> list of images to be processed
    local thread=$2					# $2 -> current thread
    for image in $full_list; do				# run in parallel
	compare "$image" "$thread"
    done
}


compare(){
    local raw=${1%.*}$particles_star_suffix
    local local=${1%.*}_local.star
    local gctf_log=${1%.*}_gctf.log
    local output="${1%.*}_deltaUV.dat"
    local output_eps="${1%.*}.eps"
    local micrograph="${1##*/}"
    local bad_output="${bad_output%.dat}_$2.tmp"				# write results to thread-specific file
    local max_output="${max_output%.dat}_$2.tmp"				# write results to thread-specific file
    # create _deltaUV.dat file so that the progress function can monitor progress
    echo -e "CoordinateX\tCoordinateY\trawDefocusU\trawDefocusV\tlocalDefocusU\tlocalDefocusV\tdeltaDefocusU\tdeltaDefocusV" > $output
    # check if all files are present
    if [ ! -s $raw ]; then
#        echo "Warning: $raw file not found!"				# TODO: echo this to err.log
        echo $micrograph >> $bad_output
        return
    fi

    if [ ! -s $local ]; then
#        echo "Warning: $local file not found!"
        echo $micrograph >> $bad_output
        return
    fi
    if [ ! -s $gctf_log ]; then
#        echo "Warning: $gctf_log file not found!"
        echo $micrograph >> $bad_output
        return
    fi
    # now check log for errors ("nan", "inf")
    nan="$(grep "nan" $gctf_log)"
    if [ "$nan" != "" ]; then 
        echo $micrograph >> $bad_output
        return
    fi
    nan="$(grep "inf" $gctf_log)"
    if [ "$nan" != "" ]; then 
        echo $micrograph >> $bad_output
        return
    fi


    # find position of interesting columns in raw star file TODO probably these should be local variables
    raw_rlnDefocusUIndex=$(awk 'NR<50 && /_rlnDefocusU/{print $2}'	$raw | cut -c 2-)
    raw_rlnDefocusVIndex=$(awk 'NR<50 && /_rlnDefocusV/{print $2}'	$raw | cut -c 2-)
    raw_rlnCoordinateX=$(awk 'NR<50 && /_rlnCoordinateX/{print $2}'	$raw | cut -c 2-)
    raw_rlnCoordinateY=$(awk 'NR<50 && /_rlnCoordinateY/{print $2}'	$raw | cut -c 2-)

    # find position of interesting columns in local star file TODO probably these should be local variables
    local_rlnDefocusUIndex=$(awk 'NR<50 && /_rlnDefocusU/{print $2}'	$local | cut -c 2-)
    local_rlnDefocusVIndex=$(awk 'NR<50 && /_rlnDefocusV/{print $2}'	$local | cut -c 2-)

    awk 'BEGIN{}/mrc/{
    if(FILENAME==ARGV[1]){
	data_rawU[rawU_array_len++] = $'$raw_rlnDefocusUIndex';		
	data_rawV[rawV_array_len++] = $'$raw_rlnDefocusVIndex';
	data_coorX[coorX_array_len++] = $'$raw_rlnCoordinateX';		
	data_coorY[coorY_array_len++] = $'$raw_rlnCoordinateY';
    }
    if(FILENAME==ARGV[2]){
	data_localU[localU_array_len++] = $'$local_rlnDefocusUIndex'
	data_localV[localV_array_len++] = $'$local_rlnDefocusVIndex'
    }}
    END{
	for ( i = 0; i < rawU_array_len; i++ ){
	    deltaU = data_localU[i]-data_rawU[i];
	    deltaU = sqrt(deltaU*deltaU);
	    deltaV = data_localV[i]-data_rawV[i];
	    deltaV = sqrt(deltaV*deltaV);
	    printf "%12.6f\t%12.6f\t%12.6f\t%12.6f\t%12.6f\t%12.6f\t%12.6f\t%12.6f\n", data_coorX[i], data_coorY[i], data_rawU[i], data_rawV[i], data_localU[i], data_localV[i], deltaU, deltaV
        }
    }' $raw $local > $output

    # finally if everything went well, plot the graph

    echo "reset
    set terminal postscript eps size 11.69,8.27 noenhanced color font 'Helvetica,20' linewidth 2
    set key autotitle columnhead
    set output '$output_eps'
    set view map
    set size square
    set tics scale 0,0
    set yrange [] reverse
    set grid
    set title '$micrograph'
    stats '$output' using (\$5+\$6)/2:(\$7+\$8)/2 nooutput
    delta=STATS_max_x-STATS_min_x	# local defocus (U+V)/2
    meany=STATS_mean_y
    miny=STATS_min_y
    maxy=STATS_max_y			# delta defocus (delU+delV)/2
# part for fitting
    set fit quiet logfile '$output_dir/fit.log'
    a=1
    b=1
    c=20000
    f(x,y) = a*x*$apix - b*y*$apix + c			# -y because we are using reversed y axis in displayed graph
    fit f(x,y) '$output' using 1:2:(\$5+\$6)/2 via a,b,c
    tilt=acos(1/(sqrt(a*a+b*b+1)))*180/pi
    if (a == 0) {
	if (b > 0) { alfa = 90 }
	if (b < 0) { alfa = 270 }
    } else {
	if (b >= 0 && a > 0) { alfa = atan(b/a)*180/pi }
	if (b >= 0 && a < 0) { alfa = atan(b/a)*180/pi+180 }
	if (b < 0 && a < 0) { alfa = atan(b/a)*180/pi+180 }
	if (b < 0 && a > 0) { alfa = atan(b/a)*180/pi+360 }
    }
    set print \"$max_output\" append
    string1 = sprintf('$micrograph	%12.6f	%12.6f	%12.6f	%12.6f	%12.6f	%12.6f', delta, miny, meany, maxy, tilt, alfa)
    print string1

    set xlabel sprintf('defocus range: %.0f A; max difference between global and local defocus: %.0f A, tilt: %.1f deg, direction: %.0f deg', delta, maxy, tilt, alfa)
    set xtics 0,512,4096					# TODO check if the dimensions of image are actually 4096 x 4096 !!!
    set ytics 0,512,4096
    splot [0:4096] [0:4096] [] '$output' using 1:2:(\$5+\$6)/2 with points palette pointsize 2 pointtype 7 linewidth 30 title \"\"
    set output" | gnuplot
}

star_replace(){									# this function is heavily based on star_replace_UVA.com script
										# created by Kai Zhang
										# http://www.mrc-lmb.cam.ac.uk/kzhang/useful_tools/
    # define all files
    local raw_starfile="$1"							# raw star file (shiny.star, particles.star etc)
    local new_starfile=${raw_starfile%.star}_localUVA.star			# new star file with replaced UVA columns
    local all_localstarfiles=${raw_starfile%.star}_all_local.star		# temporary star file with all local values

    local local_starfiles=( $2 )						# load all star files into array
    local first_localstarfile=${local_starfiles[0]}				# first local star file -> read header from it


    # copy header of raw star file
    local headN=$(awk 'NR < 100 {if($2 ~ /#/)N=NR;}END{print N}' $raw_starfile)
    gawk 'NR <= '$headN'' $raw_starfile > $new_starfile

    # copy header of local star file
    headN=$(awk 'NR < 100 {if($2 ~ /#/)N=NR;}END{print N}'  $first_localstarfile)
    awk 'NR <= '$headN''  $first_localstarfile > $all_localstarfiles

    # find position of interesting columns in raw star file
    local raw_rlnImageNameIndex=$(awk 'NR<50 && /_rlnImageName/{print $2}' $raw_starfile  | cut -c 2-)
    local raw_rlnDefocusUIndex=$(awk 'NR<50 && /_rlnDefocusU/{print $2}'  $raw_starfile | cut -c 2-)
    local raw_rlnDefocusVIndex=$(awk 'NR<50 && /_rlnDefocusV/{print $2}'  $raw_starfile | cut -c 2-)
    local raw_rlnDefocusAngleIndex=$(awk 'NR<50 && /_rlnDefocusAngle/{print $2}'  $raw_starfile | cut -c 2-)
    local raw_rlnMicrographNameIndex=$(awk 'NR<50 && /_rlnMicrographName/{print $2}' $raw_starfile  | cut -c 2-)

    # find position of interesting columns in local star file
    local local_rlnImageNameIndex=$(awk 'NR<50 && /_rlnImageName/{print $2}' $first_localstarfile  | cut -c 2-)
    local local_rlnDefocusUIndex=$(awk 'NR<50 && /_rlnDefocusU/{print $2}'  $first_localstarfile | cut -c 2-)
    local local_rlnDefocusVIndex=$(awk 'NR<50 && /_rlnDefocusV/{print $2}'  $first_localstarfile | cut -c 2-)
    local local_rlnDefocusAngleIndex=$(awk 'NR<50 && /_rlnDefocusAngle/{print $2}'  $first_localstarfile | cut -c 2-)
    local local_rlnMicrographNameIndex=$(awk 'NR<50 && /_rlnMicrographName/{print $2}' $first_localstarfile  | cut -c 2-)

    # find position of last column in local star file
    local local_keywordN=$(awk 'NR < 100 {if( $1 ~ "_rln" &&  $2 ~ /#/ )N++;}END{print N }' $first_localstarfile)
    local local_keywordNplus=$(awk 'NR < 100 {if( $1 ~ "_rln" &&  $2 ~ /#/ )N++;}END{print N + 1 }' $first_localstarfile)

    # generate an entire stack of particle after local CTF refinement 
    for localstarfile in "${local_starfiles[@]}"
    do
	awk '/mrc/{i++; printf("%s  %06d\n",$0, i)}' $localstarfile >> $all_localstarfiles
    done
    # replace UVA values
    gawk 'BEGIN{}/mrc/{
            if(FILENAME==ARGV[1]){					# 1. preprocess raw file
		image=$'$raw_rlnImageNameIndex';
		split(image, strimage, "@");
		ImageId=strimage[1]; 
		gsub("^0*", "", ImageId); 			  	    # remove leading zeros
		ImageName=$'$raw_rlnMicrographNameIndex';
		n=split(ImageName, strimage2, "/"); 		  	    # separate filename from path
		ImageName=strimage2[n]; 			  	    # remove path
		counter++;					  	    # create counter that saves the original order of particles
		zero_counter = sprintf("%09d", counter)			    # add leading zeroes so that the counter can be used for sorting
		data_raw[zero_counter"@"ImageId"@"ImageName] = $0; }	    # create array[counter@particle@image] = dataline
	    if(FILENAME==ARGV[2]){					# 2. preprocess local files
		ImageId=$'$local_keywordNplus'; 			    # particle number is in additional column
		gsub("^0*", "", ImageId); 				    # remove leading zeros
		ImageName=$'$local_rlnMicrographNameIndex'; 
		n=split(ImageName, strimage2, "/"); 	    	 	    # separate filename from path
		ImageName=strimage2[n]; 		    	 	    # remove path
		data_local[ImageId"@"ImageName] = $0; } 		    # create array[particle@image] = dataline [without counter!!!]
	}END{
	    n = asorti(data_raw, data_raw_sorted)			# 3. sort array according to the counter (== original order of particles)
            for (key in data_raw_sorted) { 				# 4. loop through all records in sorted array
	        n_raw=split(data_raw[data_raw_sorted[key]], str_raw, " ");  	# create array with all columns for this record of raw file
		gsub("^[0-9]+@*", "", data_raw_sorted[key]); 		    	# remove counter from index
	        n_local=split(data_local[data_raw_sorted[key]], str_local, " ");# create array with all columns for this record of local file
	        for (j=1;j<=n_raw;j++){				    		# loop through all columns in raw record
	            if        ( j == '$raw_rlnDefocusUIndex' 	 && str_local['$local_rlnDefocusUIndex'] != "")     {printf("%s  ",str_local['$local_rlnDefocusUIndex']);
	            } else if ( j == '$raw_rlnDefocusVIndex'     && str_local['$local_rlnDefocusVIndex'] != "")     {printf("%s  ",str_local['$local_rlnDefocusVIndex']);
	            } else if ( j == '$raw_rlnDefocusAngleIndex' && str_local['$local_rlnDefocusAngleIndex'] != "") {printf("%s  ",str_local['$local_rlnDefocusAngleIndex']);
	            } else printf("%11s  ",str_raw[j]);				# min. width = 11 characters
	        }
        	printf("\n");							# writing new record finished, now report any errors
		if ( str_local['$local_rlnDefocusUIndex'] == "") 	  {print "Warning: missing new rlnDefocusUIndex value for particle " data_raw_sorted[key] > "/dev/stderr"};
		if ( str_local['$local_rlnDefocusVIndex'] == "") 	  {print "Warning: missing new rlnDefocusVIndex value for particle " data_raw_sorted[key] > "/dev/stderr"};
		if ( str_local['$local_rlnDefocusAngleIndex'] == "") {print "Warning: missing new rlnDefocusAngleIndex value for particle " data_raw_sorted[key] > "/dev/stderr"};
	    }
	}'   $raw_starfile   $all_localstarfiles >> $new_starfile
    echo " " >> $new_starfile					# last line is empty in most star files...
    echo "new star file $new_starfile generated."
    # clean up...
    rm -rf $all_localstarfiles
}


####################################################################################################
### 01. Read arguments provided by user                                                          ###
####################################################################################################

# CtfFind job number:
echo "Provide CtfFind job number (for reading micrographs and Gctf parameters):"
while true
do
    read -p ' -> CtfFind job number [e.g. 001]: ' CtfFind_job_nr
    if [ "$CtfFind_job_nr" == "" ]; then
        echo "Use one of the following job numbers:"
	if [ -d CtfFind ]; then ls -ld CtfFind/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'; fi
	continue;
    fi
    CtfFind_job_dir="$(find */job* -maxdepth 0 -type d | grep job$CtfFind_job_nr)"
    CtfFind_job_type=$(echo $CtfFind_job_dir | cut -d'/' -f 1)
    if [ "$CtfFind_job_type" == "CtfFind" ]; then
	break;
    else
	echo "Sorry, job type $CtfFind_job_type is not proper job type (CtfFind)."
	echo "Use one of the following job numbers:"
	if [ -d CtfFind ]; then ls -ld CtfFind/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'; fi
    fi
done

# Extract/Polish job number:
echo "Provide Extract/Polish job number (for reading particles):"
while true
do
    read -p ' -> Extract/Polish job number [e.g. 001]: ' particles_job_nr
    if [ "$particles_job_nr" == "" ]; then
        echo "Use one of the following job numbers:"
#	if [ -d Refine3D ]; then ls -ld Refine3D/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'; fi
	if [ -d Extract ]; then ls -ld Extract/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'; fi
	if [ -d Polish ]; then ls -ld Polish/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'; fi
	continue;
    fi
    particles_job_dir="$(find */job* -maxdepth 0 -type d | grep job$particles_job_nr)"
    particles_job_type=$(echo $particles_job_dir | cut -d'/' -f 1)
    if [ "$particles_job_type" == "Polish" -o "$particles_job_type" == "Extract" ]; then
        break;			# TODO: test if it is not Polish / train job type...
    else
	echo "Sorry, job type $particles_job_type is not proper job type (Extract/Polish)."
	echo "Use one of the following job numbers:"
#	if [ -d Refine3D ]; then ls -ld Refine3D/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'; fi
	if [ -d Extract ]; then ls -ld Extract/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'; fi
	if [ -d Polish ]; then ls -ld Polish/* | awk '{out="\t"; for(i=9;i<=NF;i++){out=out" "$i}; print out}'; fi
    fi
done

# define name of particles star file and file suffix #TODO implement Refine3D
if [ "$particles_job_type" == "Polish" ]; then
    particles_star_file="shiny.star"
    particles_star_suffix="_shiny.star"
elif [ "$particles_job_type" == "Extract" ]; then
    particles_star_file=particles.star
    particles_star_suffix="_extract.star"
fi
if [ ! -f $particles_job_dir/$particles_star_file ]; then
    echo "ERROR: file $particles_job_dir/$particles_star_file doesn't exist, quitting..."
    exit
fi

# define and create output_dir
echo "Provide output directory:"
default_output_dir="Extra/gctf_local_${CtfFind_job_nr}_${particles_job_nr}"
read -ep ' -> Output directory [default: '$default_output_dir']: ' output_dir
if [ "$output_dir" == "" ]; then
    output_dir=$default_output_dir
else
    output_dir=${output_dir%/}						# remove trailing /
fi

if [ -d $output_dir ]; then
    echo "Output directory $output_dir already exists, running script in 'continue' mode..."
    continue_job=true
else
    continue_job=false
    echo "creating output directory: $output_dir"
    mkdir -p $output_dir						# !!! TODO option -p is not safe in all systems...
fi

# get subfolder with data from particles star file
_rlnMicrographName=`gawk 'NR<50 && /_rlnMicrographName/{print $2}' $particles_job_dir/$particles_star_file |cut -c 2- `
subdir=$(grep -m1 "mrc" $particles_job_dir/$particles_star_file | awk '{print $'$_rlnMicrographName'}')
subdir="${subdir%/*}"
subdir="${subdir##*job???/}"

# prepare "[../]xn string for local path in symlinks
IFS="/" read -ra output_dir_array <<< $output_dir		# split path into array
IFS="/" read -ra subdir_array <<< $subdir			# split path into array
output_dir_path=""						# path to project directory from output_dir
subdir_path=""							# path to output_dir from subdir
for i in "${output_dir_array[@]}"; 	do output_dir_path="${output_dir_path}../" 	; done
for i in "${subdir_array[@]}"; 		do subdir_path="${subdir_path}../"		; done

####################################################################################################
### 02. create Micrographs subdirectory, prepare star files and symlink mrc files                ###
####################################################################################################

# prepare data (if this is first time)					# TODO: re-think it -> maby it is worth to always copy all directorys
if [ "$continue_job" = false ]; then					# first round
    mkdir -p $output_dir/$subdir					# TODO: info: -p is not safe for all systems, consider different option for making subfolders
    # copy all star files from Polish job without first line (comment)
    for f in $particles_job_dir/$subdir/*$particles_star_suffix; do 	# select all files with proper suffix for chosen job type
	first_char=$(head -c 1 $f)					# read first character of star file -> if it is #, skip first line
	filename=${f##*/}						# full filename
	if [ "$first_char" = "#" ]; then				# RELION beta star file -> skip first line
	    tail -n +2 $f > $output_dir/$subdir/$filename
	else								# regular RELION star file -> copy it 
	    cp $f $output_dir/$subdir/$filename
	fi
    done
    # symlink to images from CtfFind for corresponding particles.star files
    for f in $output_dir/$subdir/*$particles_star_suffix; do		# symlink only files with corresponding shiny.star files
									# TODO: check if all images were present in CtfFind directory
	filename=${f##*/}						# full filename
	filename=${filename//$particles_star_suffix/.mrc}				# replace _shiny.star with .mrc extension
        ln -s $subdir_path$output_dir_path$CtfFind_job_dir/$subdir/$filename $output_dir/$subdir/$filename	
    done
    # symlink particles star file
    ln -s $output_dir_path$particles_job_dir/$particles_star_file $output_dir/$particles_star_file
    # !!!TODO: implement Refine3D files here !!!
fi


####################################################################################################
### 03. Prepare list of files to be processed                                                    ###
####################################################################################################

echo -n "Preparing list of files... "

# first create list of micrographs that need processing
micrographs=$output_dir/micrographs.dat						# list of files to be processed

echo -n "" > $micrographs							# empty existing list
										# !!!TODO remove it in the end
for f in $output_dir/$subdir/*.mrc; do
    if [ ! -s ${f%.*}_local.star ]; then 					# use only files without corresponding _local.star file
        echo "${f##*/}" >> $micrographs						# add filename (without path) to the list
    fi
done

number_of_files=$(wc -l < $micrographs)						# number of micrographs for processing
number_of_micrographs=$(ls 2>/dev/null -Ubad1 -- "$output_dir"/$subdir/*.mrc | wc -l)		# total number of micrographs
run_gctf_bool=true

if [ ! -s $micrographs ]; then							# doesn't exist or is empty
    echo -e "All micrographs processed - skipping Gctf calculations..."	# !!!TODO some following steps might be still required...
    run_gctf_bool=false
else
    echo "Number of files to be processed: $number_of_files"
    run_gctf_bool=true
fi

####################################################################################################
### 04. Process run.job file from CtfFind dir and get all Gctf parameters:                       ###
####################################################################################################

max_threads="16"		# max number of threads used for parallel processing in this script

if [ "$run_gctf_bool" = true ]; then							# Gctf calculations will be performed
    #define Gctf exe from RELION environment
    Gctf_exe=$RELION_GCTF_EXECUTABLE
    if [ "$Gctf_exe" == "" ]; then 
        echo "Gctf executable (\$RELION_GCTF_EXECUTABLE) not specified!"
        exit
    fi

    #initialize parameters for Gctf
    input_Gctf_option_manually=false	# if true, then all parameters will be provided by user
    apix=""
    cs=""
    kv=""
    ac=""
    astm=""
    logsuffix="_gctf.log"	# force this option
    do_EPA="1"			# force this option
    do_local_refine="1"		# force this option to calculate local defocus values
    boxsuffix="$particles_star_suffix"	# !!! change dynamically depending on job type
    do_validation="1"		# Whether to validate the CTF determination.
    ctfstar="NULL"		# Output star files to record all CTF parameters. Use 'NULL' or 'NONE' to skip writing out the CTF star file.
    write_local_ctf="0"		# Whether to write out a diagnosis power spectrum file for each particle.
    gid="0"			# GPU id, default = 0; can be changed later on
    batch_size="16"		# max number of micrographs processed by single Gctf process

    # Process run.job file and get all necessary parameters:
    apix="$(	grep "Magnified pixel size (Angstrom):" $CtfFind_job_dir/run.job | awk -F " == " '{print $2}')"
    cs="$(	grep "Spherical aberration (mm):" 	$CtfFind_job_dir/run.job | awk -F " == " '{print $2}')"
    kv="$(	grep "Voltage (kV):" 			$CtfFind_job_dir/run.job | awk -F " == " '{print $2}')"
    ac="$(	grep "Amplitude contrast:" 		$CtfFind_job_dir/run.job | awk -F " == " '{print $2}')"
    astm="$(	grep "Amount of astigmatism (A):"	$CtfFind_job_dir/run.job | awk -F " == " '{print $2}')"

    if [ "$apix" == "" ]; then echo "Warning: Magnified pixel size (apix) not specified!"; 	input_Gctf_option_manually=true; fi
    if [ "$cs" == "" ];   then echo "Warning: Spherical aberration (cs) not specified!"; 	input_Gctf_option_manually=true; fi
    if [ "$kv" == "" ];   then echo "Warning: Voltage (kv) not specified!"; 			input_Gctf_option_manually=true; fi
    if [ "$ac" == "" ];   then echo "Warning: Amplitude contrast (ac) not specified!"; 		input_Gctf_option_manually=true; fi
    if [ "$astm" == "" ]; then echo "Warning: Amount of astigmatism (astm) not specified!";	input_Gctf_option_manually=true; fi

    # check/ask if parameters needs to be edited
    if [ "$input_Gctf_option_manually" = false ]; then
        echo "Gctf options from job $CtfFind_job_dir: apix = $apix; cs = $cs; kv = $kv; ac = $ac; astm = $astm"
        echo "Default GPU id = $gid; max number of threads = $max_threads"
        read -p ' -> do you want to edit these parameters? [y/n]: ' yn
        case $yn in
            [yY][eE][sS]|[yY])					# case-insensitive yes/y
                input_Gctf_option_manually=true
    	        ;;
	    *) ;;
        esac
    else
        echo "Gctf options from file $CtfFind_job_dir/run.job: apix = $apix; cs = $cs; kv = $kv; ac = $ac; astm = $astm"
    fi

    # edit Gctf parameters
    if [ "$input_Gctf_option_manually" = true ]; then
        echo "Provide new parameters:"
        apix=$(read_input_float "Magnified pixel size (Angstrom)" $apix)
          cs=$(read_input_float "Spherical aberration (mm)" $cs)
          kv=$(read_input_float "Voltage (kV)" $kv)
          ac=$(read_input_float "Amplitude contrast" $ac)
        astm=$(read_input_float "Amount of astigmatism (A)" $astm)
        gid=$(read_input_float "GPU id" $gid)
        max_threads=$(read_input_float "Maximum number of threads used for parallel calculations" $max_threads)
        echo "Final Gctf options: apix = $apix; cs = $cs; kv = $kv; ac = $ac; astm = $astm"
        echo "GPU id = $gid; max number of threads = $max_threads"
    fi
fi

####################################################################################################
### 05. Run Gctf                                                                                 ###
####################################################################################################

# run it only if list of micrographs is not empty!
if [ "$run_gctf_bool" = true ]; then							# Gctf calculations will be performed
    # first divide list of micrographs into threads
    current_thread="1"
    while read line; do							  	# not recommended option but easiest and should work here
	image_list[$current_thread]="${image_list[$current_thread]} $output_dir/$subdir/$line"
	((current_thread++))
	if [ "$current_thread" -gt "$max_threads" ]; then
		current_thread="1"
	fi
    done < $micrographs

    # now start progress function and run Gctf with --do_local_refine option
    echo "Running Gctf with --do_local_refine option for these $number_of_files micrographs..."
    echo "(Note that it may take more than 1 hour to process single image with >1000 particles)..."
    progress "*_local.star" $number_of_files $((number_of_micrographs - number_of_files)) &
    MYSELF=$!									# PID of progress function
#    trap "{ sleep 1; exit; }" SIGINT SIGTERM					# wait till all is killed and displayed and end script
    trap "{ sleep 1; }" SIGINT SIGTERM					# wait till all is killed and displayed and end script

    for f in "${!image_list[@]}"; do 						# loop through keys in this array (!!)
	run_gctf "${image_list[$f]}" $f &
	pids[${f}]=$!
    done

    for pid in ${pids[*]}; do wait $pid ; done     				# wait for all Gctf pids
    trap - SIGINT SIGTERM							# deactivate trap
    kill $MYSELF > /dev/null 2>&1						# kill progress function
    wait > /dev/null 2>&1							# this will clean the message 'terminated...'
	
    echo ""
    echo "Gctf finished..."
fi

####################################################################################################
### 06. Analyse Gctf results, check for errors and prepare diagnostic files                      ###
####################################################################################################

max_output="${output_dir}/maxDeltaUV.dat"
bad_output="${output_dir}/bad_micrographs.dat"
run_compare_bool=true

if [ -s $max_output ] && [ "$run_gctf_bool" = false ] ; then			# file exists and is not empty && Gctf was not running 
										# -> ask if run this script... TODO: check if it works for both conditions
    echo "File $max_output already exists - it seems that the data were already processed..."
    read -p ' -> Do you want to compare raw and local UVA values again? [y/n]: ' yn
    case $yn in
        [yY][eE][sS]|[yY])							# case-insensitive yes/y
            run_compare_bool=true ;;
	*) 
	    run_compare_bool=false ;;
    esac
fi

if [ "$run_compare_bool" = true ] ; then
    # first divide list of micrographs into threads
    if [ "$run_gctf_bool" = false ]; then					# Gctf was not performed -> ask for max_threads
        max_threads=$(read_input_float "Maximum number of threads used for parallel calculations" $max_threads)
    fi

    current_thread="1"
    unset image_list								# clear array from previous list
    for f in $output_dir/$subdir/*.mrc; do
	image_list[$current_thread]="${image_list[$current_thread]} $f"
	((current_thread++))
	if [ "$current_thread" -gt "$max_threads" ]; then
		current_thread="1"
	fi
    done

    # compare values...
    echo "comparing raw and local values for each micrograph and checking for errors..."
    echo -e "micrograph name\tlocal defocus range\tmin defocus difference\taverage defocus difference\tmax defocus difference\ttilt angle\ttilt direction" \
		> $max_output; # empty existing list and create header
    echo -n "" > $bad_output							# empty existing list

    rm $output_dir/$subdir/*_deltaUV.dat > /dev/null 2>&1			# remove ALL previous values

    progress "*_deltaUV.dat" $number_of_micrographs 0 &				# monitor progress of calculations
    MYSELF=$!									# PID of progress function
    for f in "${!image_list[@]}"; do 						# loop through keys in this array (!!)
	run_compare "${image_list[$f]}" $f &
	pids[${f}]=$!
    done

    for pid in ${pids[*]}; do wait $pid ; done     				# wait for all run_compare pids

    kill $MYSELF > /dev/null 2>&1						# kill progress function
    wait > /dev/null 2>&1							# this will clean the message 'terminated...'

    echo -e "\ncomparing finished..."

    # now sort and remove partial files
    sort $output_dir/maxDeltaUV_*.tmp >> $max_output 2> /dev/null
    sort $output_dir/bad_micrographs_*.tmp >> $bad_output 2> /dev/null
    rm $output_dir/maxDeltaUV_*.tmp 2> /dev/null
    rm $output_dir/bad_micrographs_*.tmp 2> /dev/null
fi



####################################################################################################
### 07. Create pdf report                                                                        ###
####################################################################################################

if [ "$run_compare_bool" = true ] && [ $(wc -l < $max_output) -gt 2 ] ; then			# if it didn't run the report should be there
    graph1="$output_dir/local_defocus_range.eps"
    title="Local defocus range (max-min) for all micrographs"
    xlabel="micrograph number"
    ylabel="local defocus range [A]"
    plot_data $max_output $graph1 "$title" "$xlabel" "$ylabel" "0:2 with lines"

    graph2="$output_dir/max_defocus_difference.eps"
    title="Difference between global and local defocus (average with min and max values) for all micrographs"
    xlabel="micrograph number"
    ylabel="defocus difference [A]"
    plot_data $max_output $graph2 "$title" "$xlabel" "$ylabel" "0:5:3 with filledcurve fc rgb \"orange\" title \"\", '' using 0:4 with lines"

    graph3="$output_dir/tilt_angle.eps"
    title="Tilt angle (calculated based on local defocus)"
    xlabel="micrograph number"
    ylabel="tilt angle [deg]"
    plot_data $max_output $graph3 "$title" "$xlabel" "$ylabel" "0:6 with lines"

    graph4="$output_dir/tilt_direction.eps"
    title="Tilt direction (claculated based on local defocus)"
    xlabel="micrograph number"
    ylabel="tilt direction [deg]"
    plot_data $max_output $graph4 "$title" "$xlabel" "$ylabel" "0:7 with lines"

    # now create pdf report
    echo "creating logfile.pdf..."
    gs -sDEVICE=pdfwrite -dNOPAUSE -dBATCH -dSAFER -sOutputFile=$output_dir/logfile.pdf \
	-dEPSCrop -c "<</Orientation 2>>setpagedevice" -f $graph1 $graph2 $graph3 $graph4 \
	$output_dir/$subdir/*.eps > /dev/null 2>&1 				# TODO: might want to output it to gs log
fi

####################################################################################################
### 08. Replace raw defocus values with local values and create new particles star file          ###
####################################################################################################

run_star_replace=true
if [ -s $bad_output ]; then						# file exists and is not empty -> ask if run this script...
    while read line; do
	echo -n ""
	mv $output_dir/$subdir/${line%.*}_local.star $output_dir/$subdir/${line%.*}_local.star.bad > /dev/null 2>&1 
	mv $output_dir/$subdir/${line%.*}_gctf.log $output_dir/$subdir/${line%.*}_gctf.log.bad > /dev/null 2>&1 
	mv $output_dir/$subdir/${line%.*}_deltaUV.dat $output_dir/$subdir/${line%.*}_deltaUV.dat.bad > /dev/null 2>&1 # TODO: this line can be most likely removed -> if there were errors, no deltaUV file was created...
    done < $bad_output
    number_of_bad_files=$(wc -l < $bad_output)
    echo "WARNING: $number_of_bad_files files were not processed properly by Gctf (see $bad_output for full list)."
    echo "You may want to check what went wrong and run this script again to reprocess these files."
    read -p ' -> Do you want to run star_raplace_UVA_MCC.com script anyway? [y/n]: ' yn
    case $yn in
        [yY][eE][sS]|[yY])					# case-insensitive yes/y
            run_star_replace=true ;;
	*) 
	    run_star_replace=false ;;
    esac
else
    echo "It seems that Gctf processed all files succesfully!"
fi

if [ $run_star_replace = true ]; then
    echo "Running star_replace_UVA_MCC.com script (by Kai Zhang, modified by MCC)..."
    star_replace "$output_dir/$particles_star_file" "$output_dir/$subdir/*_local.star"
fi

echo "All done, quitting..."

####################################################################################################
### 09. Clean-up                                                                                 ###
####################################################################################################


# clean-up
rm $micrographs
if [ ! -s $bad_output ]; then rm $bad_output > /dev/null 2>&1 ; fi;		# only if empty, ignore error if not present
