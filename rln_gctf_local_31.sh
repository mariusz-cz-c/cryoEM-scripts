#!/bin/bash
# Mariusz Czarnocki-Cieciura,   16.01.2019
# last modification:            11.05.2020
# it uses part of the script star_replace_UVA.com by Kai Zhang
# http://www.mrc-lmb.cam.ac.uk/kzhang/useful_tools/

# dependencies: gawk

echo "+---------------------------------------------------------------------------------------+"
echo "  script created by Mariusz Czarnocki-Cieciura, 16.01.2019"
echo "  last modification: 11.06.2020"
echo "  it uses part of the script star_replace_UVA.com by Kai Zhang"
echo "  http://www.mrc-lmb.cam.ac.uk/kzhang/useful_tools/"
echo "+---------------------------------------------------------------------------------------+"



####################################################################################################
### 00. Definitions of all functions                                                             ###
####################################################################################################

# get and print value of provided parameter; if value is different for at least one optics group, return '-1'.
read_optics_value(){					# $1 -> input micrographs star file
    local input=$1					# $2 -> column name
    local field=$2
    local OpticsGroup=`gawk '/data_optics/,/data_micrographs/ {if(/_rlnOpticsGroup /) print $2}' $input |cut -c 2- `	# space in if() is important to discriminate between _rlnOpticsGroup and _rlnOpticsGroupName
															# TODO !!! this is not used anymore!!!
    # get column position for the selected field
    local column=`gawk '/data_optics/,/data_micrographs/ {if(/'$field'/) print $2}' $input |cut -c 2- `	
    if [ "$column" = "" ]; then 
        echo "ERROR: could not find $field field in $input, quitting!" 1>&2
        exit
    fi
    # read ALL values for selected column and check if they are ALL the same
    local value=`gawk 'BEGIN{}	
        /^#/ {next} 												# skip lines with comments
        /data_optics/,/data_micrographs/ {									# parse only data_optics table
            if (NF > 2) {											# more than 2 columns -> data
                !($'$column' in data) data[$'$column']; }							# add only unique elements to data[] array
            }END{												# now process the array
                if (length(data) > 1) 										# more than one value -> return -1
                    print "-1";
                else 												# only single value -> print it 
                    for (key in data) print key; 							
    }' $input`
    if [ "$value" = "-1" ]; then 
        echo "ERROR: field $field has different values for different Optics Groups! Please process micrographs with different $field values separately!" 1>&2
        exit
    fi
    echo $value
}

# convert input string into int from provided range
make_int(){					
    local input=$1				# $1 -> input string
    local min=$2				# $2 -> min value
    local max=$3				# $3 -> max value 
    local default_value=$4			# $4 -> default value
    local value=""
    is_int="^-?[0-9]+$"				# regular expression match for integer
    if [[ $input =~ $is_int ]] && [ "$input" -ge "$min" ] && [ "$input" -le "$max" ] ; then
	value=$input	
    else
	value=$default_value;
    fi
    echo $value
}

# get and print column position of provided parameter; if parameter is not found, quit script
get_column_position(){	
    local input_star=$1
    local column_name=$2
    value=$(gawk 'NR<100 && /'$column_name'/{print $2}'		$input_star | cut -c 2-)	# this should be unique to data_particles table
    if [ "$value" = "" ]; then 
        echo "ERROR: could not find $column_name field in $input_star, quitting!" 1>&2
        exit
    fi
    echo $value
}

# trap launched when progress() function is killed -> displays final counter and quits script
progress_trap(){
    local search_pattern=$1				# $1 -> search pattern inside Micrographs subdirectory
    local MAX_NUMBER=$2					# $2 -> number of files to be processed
    local SKIP_FILES=$3					# $3 -> number of files to be skipped	
    local counter=$(find $output_dir/$subdir -type f ! -empty -name $search_pattern | wc -l)
    counter=$((counter-SKIP_FILES)) 
    local duration=$SECONDS
    local ETA="0"
    local percent=$(awk "BEGIN {print 100*$counter/$MAX_NUMBER}")				# float percent progress
    echo -en "\rProcessing Images: [==================================================] "
    echo -en "$percent% ($counter out of $MAX_NUMBER), "
    TZ=UTC0	printf 'time: %(%H:%M:%S)T, ETA: %(%H:%M:%S)T' "$duration" "$ETA"
    exit
}

# progress bar function
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
		percent=$(awk "BEGIN {print 100*$counter/$MAX_NUMBER}")		# float percent progress
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
	local batch_number="0"
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
		echo $gctf_command >> $output_dir/gctf_local_commands.log
	done
}


run_compare(){
    local full_list=$1					# $1 -> list of images to be processed
    local thread=$2					# $2 -> current thread
    for image in $full_list; do				# run in parallel
	compare "$image" "$thread"
    done
}


compare(){
    local raw=${1%.*}_coordinates.star
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
        echo "WARNING: $raw file not found!" 1>&2
        echo $micrograph >> $bad_output
        return
    fi

    if [ ! -s $local ]; then
        echo "WARNING: $local file not found!" 1>&2
        echo $micrograph >> $bad_output
        return
    fi
    if [ ! -s $gctf_log ]; then
        echo "WARNING: $gctf_log file not found!" 1>&2
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

    # check image dimensions with relion_image_handler						# TODO: this migh be slow...
    image_stats=$(relion_image_handler --i $1 --stats)
    image_sizex=$(echo $image_stats | awk '{print $4}')
    image_sizey=$(echo $image_stats | awk '{print $6}')

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
#    set size square
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
    c=20000								# defocus in A
    f(x,y) = a*x*$apix - b*y*$apix + c					# -y because we are using reversed y axis in displayed graph
    fit f(x,y) '$output' using 1:2:(\$5+\$6)/2 via a,b,c		# use average defocus: (U+V)/2
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
#    set xtics 0,512,4096					# TODO check if the dimensions of image are actually 4096 x 4096 !!!
#    set ytics 0,512,4096
    splot [0:$image_sizex] [0:$image_sizey] [] '$output' using 1:2:(\$5+\$6)/2 with points palette pointsize 2 pointtype 7 linewidth 30 title \"\"
    set output" | gnuplot
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


star_replace(){									# this function is heavily based on star_replace_UVA.com script
										# created by Kai Zhang
										# http://www.mrc-lmb.cam.ac.uk/kzhang/useful_tools/
    # define all files
    local raw_starfile="$1"							# raw star file
    local local_starfile="$2"							# new star file with local UVA columns
    local all_localstarfiles=${raw_starfile%.star}_all_local.star		# temporary star file with local values for ALL particles

    local local_starfiles=( $3 )						# load all local star files into array
    local first_localstarfile=${local_starfiles[0]}				# first local star file -> read header from it

    # copy header of raw star file
    local headN=$(awk 'NR < 100 {if($2 ~ /#/)N=NR;}END{print N}' $raw_starfile)
    gawk 'NR <= '$headN'' $raw_starfile > $local_starfile

    # copy header of local star file
    headN=$(awk 'NR < 100 {if($2 ~ /#/)N=NR;}END{print N}'  $first_localstarfile)
    awk 'NR <= '$headN''  $first_localstarfile > $all_localstarfiles

    # find position of interesting columns in local star file
    local local_rlnImageNameIndex=$(awk 'NR<50 && /_rlnImageName/{print $2}' $first_localstarfile  | cut -c 2-)
    local local_rlnDefocusUIndex=$(awk 'NR<50 && /_rlnDefocusU/{print $2}'  $first_localstarfile | cut -c 2-)
    local local_rlnDefocusVIndex=$(awk 'NR<50 && /_rlnDefocusV/{print $2}'  $first_localstarfile | cut -c 2-)
    local local_rlnDefocusAngleIndex=$(awk 'NR<50 && /_rlnDefocusAngle/{print $2}'  $first_localstarfile | cut -c 2-)
    local local_rlnMicrographNameIndex=$(awk 'NR<50 && /_rlnMicrographName/{print $2}' $first_localstarfile  | cut -c 2-)

    # find position of last column in local star file
    local local_keywordN=$(awk 'NR < 100 {if( $1 ~ "_rln" &&  $2 ~ /#/ )N++;}END{print N }' $first_localstarfile)
    local local_keywordNplus=$(awk 'NR < 100 {if( $1 ~ "_rln" &&  $2 ~ /#/ )N++;}END{print N + 1 }' $first_localstarfile)


    # generate an entire stack of particle after local CTF refinement with ImageId as last column
    for f in $output_dir/$subdir/*.mrc; do
        if [ ! -s ${f%.*}_coordinates.star ]; then 			
            echo "WARNING: missing *_coordinates.star file for micrograph $f!"	1>&2
	    continue
        fi
        if [ ! -s ${f%.*}_local.star ]; then 				

            echo "WARNING: missing *_local.star file for micrograph $f!"	1>&2
	    continue
        fi

	gawk 'BEGIN{}/mrc/{
	          if(FILENAME==ARGV[1]){
		      image=$'$coordinates_rlnImageNameIndex';				    # get ImageName 		-> e.g. 000228@Extract/job015/Movies/part2/FoilHole_6589019_Data_6577453_6577455_20200408_011825.mrcs
		      split(image, strimage, "@");					    # split string by @
		      ImageId=strimage[1]; 				 		    # get ImageId 		-> e.g. 00228
		      gsub("^0*", "", ImageId); 			  		    # remove leading zeros 	-> e.g. 228
		      lines[counter1++] = ImageId} 					    # add ImageID to table
		  if(FILENAME==ARGV[2]){
		      lines2[counter2++] = $0}						    # add whole line to table
	      }END{
		  for (key in lines) {
		      print lines2[key] " " lines[key]}					    # print whole line + ImageID
	      }' ${f%.*}_coordinates.star ${f%.*}_local.star >> $all_localstarfiles
    done


    # replace UVA values
    gawk 'BEGIN{}/mrc/{
            if(FILENAME==ARGV[1]){						# 1. preprocess raw file
		image=$'$global_rlnImageNameIndex';				    # get ImageName 		-> e.g. 000228@Extract/job015/Movies/part2/FoilHole_6589019_Data_6577453_6577455_20200408_011825.mrcs
		split(image, strimage, "@");					    # split string by @
		ImageId=strimage[1]; 				 		    # get ImageId 		-> e.g. 00228
		gsub("^0*", "", ImageId); 			  		    # remove leading zeros 	-> e.g. 228
		MicrographName=$'$global_rlnMicrographNameIndex';		    # get MicrographName	-> e.g. MotionCorr/job007/Movies/part2/FoilHole_6589019_Data_6577453_6577455_20200408_011825.mrc
		n=split(MicrographName, strimage2, "/"); 			    # split string by /
		MicrographName=strimage2[n]; 			  		    # remove path		-> e.g. FoilHole_6589019_Data_6577453_6577455_20200408_011825.mrc
		counter++;					  		    # create / increment counter that saves the original order of particles in raw file
		zero_counter = sprintf("%09d", counter);			    # add leading zeroes to the counter so that the counter can be used for sorting
		data_raw[zero_counter"@"ImageId"@"MicrographName] = $0; 	    # create array[counter@particle@image] = dataline
#		print "1: " zero_counter"@"ImageId"@"MicrographName > "/dev/stderr";
	        }
	    if(FILENAME==ARGV[2]){						# 2. preprocess local files
		ImageId=$'$local_keywordNplus'; 				    # get ImageID		-> e.g. 000022  (particle number is in additional column NOT listed in star header)
		gsub("^0*", "", ImageId); 					    # remove leading zeros	-> e.g. 22
		ImageName=$'$local_rlnMicrographNameIndex';			    # get ImageName		-> e.g. External/job017/Micrographs/FoilHole_6589019_Data_6577453_6577455_20200408_011825.mrc
 		n=split(ImageName, strimage2, "/"); 	    	 		    # split string by /
		ImageName=strimage2[n]; 		    	 		    # remove path		-> e.g. FoilHole_6589019_Data_6577453_6577455_20200408_011825.mrc
		data_local[ImageId"@"ImageName] = $0; 		 		    # create array[particle@image] = dataline [without counter!!!]
#		print "2: " ImageId"@"ImageName > "/dev/stderr";
	 	}
	}END{
	    n = asorti(data_raw, data_raw_sorted)				# 3. sort array according to the counter (== original order of particles)
            for (key in data_raw_sorted) { 					# 4. loop through all records in sorted array
	        n_raw=split(data_raw[data_raw_sorted[key]], str_raw, " ");  	    # create array with all columns for this record of raw file
		gsub("^[0-9]+@*", "", data_raw_sorted[key]); 		    	    # remove counter from index
	        n_local=split(data_local[data_raw_sorted[key]], str_local, " ");    # create array with all columns for this record of local file
	        for (j=1;j<=n_raw;j++){				    		    # loop through all columns in raw record
	            if        ( j == '$global_rlnDefocusUIndex' 	 && str_local['$local_rlnDefocusUIndex'] != "")     {printf("%s  ",str_local['$local_rlnDefocusUIndex']);
	            } else if ( j == '$global_rlnDefocusVIndex'     && str_local['$local_rlnDefocusVIndex'] != "")     {printf("%s  ",str_local['$local_rlnDefocusVIndex']);
	            } else if ( j == '$global_rlnDefocusAngleIndex' && str_local['$local_rlnDefocusAngleIndex'] != "") {printf("%s  ",str_local['$local_rlnDefocusAngleIndex']);
	            } else printf("%11s  ",str_raw[j]);				    # min. width = 11 characters
	        }
        	printf("\n");							    # writing new record finished, now report any errors
		if ( str_local['$local_rlnDefocusUIndex'] == "") 	  {print "WARNING: missing new rlnDefocusUIndex value for particle " data_raw_sorted[key] > "/dev/stderr"};
		if ( str_local['$local_rlnDefocusVIndex'] == "") 	  {print "WARNING: missing new rlnDefocusVIndex value for particle " data_raw_sorted[key] > "/dev/stderr"};
		if ( str_local['$local_rlnDefocusAngleIndex'] == "") {print "WARNING: missing new rlnDefocusAngleIndex value for particle " data_raw_sorted[key] > "/dev/stderr"};
	    }
	}'   $raw_starfile   $all_localstarfiles >> $local_starfile
    echo " " >> $local_starfile					# last line is empty in most star files...
    echo "new star file $local_starfile generated."
    # clean up...
#    rm -rf $all_localstarfiles
}


####################################################################################################
### 01. Read and parse input parameters                                                          ###
####################################################################################################

# initialize input parameters
input_micrographs=""
input_particles=""
output_dir=""
micrographs=""												# list of files to be processed
number_of_files=""											# number of micrographs for processing
number_of_micrographs=""										# total number of micrographs
run_gctf_bool=false											# is Gctf required?
subdir="Micrographs"											# ignore true hierarchy / path here... TODO !!! implement original subfolders
print_help_and_quit=false
continue_job=false											# is this 'continue' job type?
max_threads="8"												# max number of threads used for parallel processing in this script, default: 8



# parse input parameters
while [ $# -gt 0 ]; do
  case "$1" in
    --o)
      shift
      output_dir="${1#*=}"
      output_dir_data=$output_dir/$subdir
      ;;
    --in_mics)
      shift
      input_micrographs="${1#*=}"
      ;;
    --in_parts)
      shift
      input_particles="${1#*=}"
      ;;
    --j)
      shift
      max_threads="${1#*=}"
      ;;
    -h|--help)
      print_help_and_quit=true
      ;;
    *)
      echo "ERROR: Invalid argument: $1" 1>&2
      print_help_and_quit=true
      ;;
  esac
  shift
done

# check input parameters
if [ "$input_micrographs" = "" ]; then 
    echo "ERROR: please provide input micrographs star file from CtfFind job as --in_mics parameter!" 1>&2
    print_help_and_quit=true
elif [ ! -s $input_micrographs ]; then
    echo "ERROR: input micrographs star file $input_micrographs not found!" 1>&2
    print_help_and_quit=true
fi

if [ "$input_particles" = "" ]; then 
    echo "ERROR: please provide particles star file as --in_parts parameter! " 1>&2
    print_help_and_quit=true
elif [ ! -s $input_particles ]; then
    echo "ERROR: input particles star file $input_particles not found!"	1>&2
    print_help_and_quit=true
fi

if [ "$output_dir" = "" ]; then 
    echo "ERROR: please provide output directory as --o parameter! " 1>&2
    print_help_and_quit=true
fi

# print help message and quit
if [ "$print_help_and_quit" = true ]; then 
    echo "HELP message..."
    exit 0
fi

# parse number of threads:
max_threads=$(make_int $max_threads 1 16 8)
echo "Running the script with the following parameters:" 
echo "    input micrographs star file: $input_micrographs"
echo "    input particles star file: $input_particles"
echo "    output directory: $output_dir"
echo "    j = $max_threads number of threads on GPU #0"


####################################################################################################
### 02. Create output directory and all necessary files                                          ###
####################################################################################################

if [ -d $output_dir/$subdir ]; then
    echo "Micrographs output directory $output_dir/$subdir already exists, running script in 'continue' mode..."
    continue_job=true
else
    continue_job=false
    echo "Creating micrographs output directory $output_dir/$subdir"
    mkdir -p $output_dir/$subdir								# !!! TODO option -p is not safe in all systems...
fi


# symlink original particles star file									# TODO !!! is this necessary?
particles_global=$output_dir/particles_raw.star							# original particles star file (symbolik link)
particles_local=$output_dir/particles_localUVA.star						# new particles star file with local UVA values
ln -fs ../../$input_particles $particles_global

####################################################################################################
### 03. Get / define (and print) Gctf parameters                                                 ###
####################################################################################################

echo -n "Analysing $input_micrographs star file to get CTF fitting parameters... "

# Gctf parameters from micrographs star file
  kv=$(read_optics_value $input_micrographs "_rlnVoltage")
  cs=$(read_optics_value $input_micrographs "_rlnSphericalAberration")
  ac=$(read_optics_value $input_micrographs "_rlnAmplitudeContrast")
apix=$(read_optics_value $input_micrographs "_rlnMicrographPixelSize")

# rest of Gctf parameters:
    astm="100"					# default and probably reasonable value
    gid="0"					# GPU id, default = 0; can be changed later on TODO: this should be changeable!
    logsuffix="_gctf.log"			# force this option
    do_EPA="1"					# force this option
    do_local_refine="1"				# force this option to calculate local defocus values
    boxsuffix="_coordinates.star"		# force this option
    do_validation="1"				# Whether to validate the CTF determination.
    ctfstar="NULL"				# Output star files to record all CTF parameters. Use 'NULL' or 'NONE' to skip writing out the CTF star file.
    write_local_ctf="0"				# Whether to write out a diagnosis power spectrum file for each particle.
    batch_size="16"				# max number of micrographs processed by single Gctf process

echo "Done!"

echo "Using the following Gctf parameters:"
echo -e "    kv = $kv \t from $input_micrographs"
echo -e "    cs = $cs \t from $input_micrographs"
echo -e "    ac = $ac \t from $input_micrographs"
echo -e "  apix = $apix \t from $input_micrographs"
echo -e "  astm = $astm \t\t default value"
echo -e "   gid = $gid \t\t (GPU ID) default value"


# define Gctf exe from RELION environment

echo -n "Checking for Gctf executable (from \$RELION_GCTF_EXECUTABLE)... "

Gctf_exe=$RELION_GCTF_EXECUTABLE
if [ "$Gctf_exe" == "" ]; then 
    echo -e "ERROR! Gctf executable (\$RELION_GCTF_EXECUTABLE) not specified!" 1>&2
    exit
fi

echo "Found Gctf at $Gctf_exe"


####################################################################################################
### 04. Parse particles star file -> create star file with coordinates for each micrograph       ###
####################################################################################################

# get column position of required fields in global file:

echo -n "Analysing $input_particles star file to get header values... "

     global_rlnImageNameIndex=$(get_column_position $particles_global "_rlnImageName")
global_rlnMicrographNameIndex=$(get_column_position $particles_global "_rlnMicrographName")
   global_rlnCoordinateXIndex=$(get_column_position $particles_global "_rlnCoordinateX")
   global_rlnCoordinateYIndex=$(get_column_position $particles_global "_rlnCoordinateY")
      global_rlnDefocusUIndex=$(get_column_position $particles_global "_rlnDefocusU")
      global_rlnDefocusVIndex=$(get_column_position $particles_global "_rlnDefocusV")
  global_rlnDefocusAngleIndex=$(get_column_position $particles_global "_rlnDefocusAngle")

echo "Done!"

# define column position of required fields for local files:

     coordinates_rlnImageNameIndex=1
coordinates_rlnMicrographNameIndex=2
   coordinates_rlnCoordinateXIndex=3
   coordinates_rlnCoordinateYIndex=4
      coordinates_rlnDefocusUIndex=5
      coordinates_rlnDefocusVIndex=6
  coordinates_rlnDefocusAngleIndex=7


# create symbolic links to mrc files
echo -n "Creating symbolic links to all mrc files... "

gawk 'BEGIN{}	
        /data_particles/,0 {											# parse only data_particles table
            if (/mrc/) {											# only data fields contain mrc string
                !($'$global_rlnMicrographNameIndex' in data) data[$'$global_rlnMicrographNameIndex']; }
            }END{												# now process the array
                    for (key in data) {
                        n = split(key, array, "/")								# filename = array[n]
                        # print n " -> " array[n];
                        system("ln -fs " "../../../" key " '$output_dir/$subdir'/" array[n] ); }		# create symbolic link to original mrc file
                    
    }' $particles_global											# TODO !!! double-check if this is OK in all cases (nested directories etc)

echo "Done!"



# create star files with proper header
echo -n "Creating star files with particle coordinates for each mrc file... "

# start with header:
for f in $output_dir/$subdir/*.mrc; do 
    echo -e "\ndata_\n\nloop_\n_rlnImageName #$coordinates_rlnImageNameIndex \n_rlnMicrographName #$coordinates_rlnMicrographNameIndex \n_rlnCoordinateX #$coordinates_rlnCoordinateXIndex \n_rlnCoordinateY #$coordinates_rlnCoordinateYIndex \n_rlnDefocusU #$coordinates_rlnDefocusUIndex \n_rlnDefocusV #$coordinates_rlnDefocusVIndex \n_rlnDefocusAngle #$coordinates_rlnDefocusAngleIndex " > ${f%*.mrc}_coordinates.star; 
done

# now add coordinates to each file. Global defocus values are also printed for future comparisons.

gawk '/data_particles/,0 {
            if (/mrc/) {											# only data fields contain mrc string		
                filename=$'$global_rlnMicrographNameIndex';									# get MicrographName
                sub(".*/", "", filename);									# get filename - strip path
                sub(".mrc", "_coordinates.star", filename);							# get filename - replace *.mrc with _coordinates.star
                printf "%s %s %12.6f %12.6f %12.6f %12.6f %12.6f\n", $'$global_rlnImageNameIndex',$'$global_rlnMicrographNameIndex', $'$global_rlnCoordinateXIndex', $'$global_rlnCoordinateYIndex', $'$global_rlnDefocusUIndex', $'$global_rlnDefocusVIndex', $'$global_rlnDefocusAngleIndex'  >> "'$output_dir/$subdir'/"filename }	# append coordinates to star file
            }' $particles_global

echo "Done!"


####################################################################################################
### 05. Prepare list of files to be processed                                                    ###
####################################################################################################

echo "Preparing list of files for processing..."
echo -n "(Note: only mrc files without corresponding *_local.star files will be processed)... "
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
    echo -e "Done! \nAll ($number_of_micrographs) micrographs processed - skipping Gctf calculations..."	# !!!TODO some following steps might be still required...
    run_gctf_bool=false
else
    echo -e "Done! \nNumber of micrographs to be processed: $number_of_files"
    run_gctf_bool=true
fi



####################################################################################################
### 06. Run Gctf                                                                                 ###
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
### 07. Analyse Gctf results, check for errors and prepare diagnostic files                      ###
####################################################################################################

max_output="${output_dir}/maxDeltaUV.dat"					# output file with maximum delta defocus for each micrograph
bad_output="${output_dir}/bad_micrographs.dat"					# output file with micrographs with processing errors

if [ -s $max_output ] && [ "$run_gctf_bool" = false ] ; then			# file exists and is not empty && Gctf was not running 
										# -> ask if run this script... TODO: check if it works for both conditions
    echo "File $max_output already exists - it seems that the data were already processed!"
    echo "If you want to re-process some images, remove corresponding *_local.star files from output directory. "
    echo "If you want to re-calculate the particles_localUVA.star, remove $max_output file. "
    exit									# TODO: !!! add some more comments here???
fi

# first divide list of micrographs into threads

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
echo "Comparing raw and local values for each micrograph and checking for errors..."
echo -e "micrograph name\tlocal defocus range\tmin defocus difference\taverage defocus difference\tmax defocus difference\ttilt angle\ttilt direction" \
	> $max_output; 								# empty existing list and create header
echo -n "" > $bad_output							# empty existing list

rm $output_dir/$subdir/*_deltaUV.dat > /dev/null 2>&1				# remove ALL previous values

progress "*_deltaUV.dat" $number_of_micrographs 0 &				# monitor progress of calculations
MYSELF=$!									# PID of progress function
for f in "${!image_list[@]}"; do 						# loop through keys in this array (!!)
    run_compare "${image_list[$f]}" $f &
    pids[${f}]=$!
done

for pid in ${pids[*]}; do wait $pid ; done     					# wait for all run_compare pids

kill $MYSELF > /dev/null 2>&1							# kill progress function
wait > /dev/null 2>&1								# this will clean the message 'terminated...'

echo -e "\ncomparing finished..."

# now sort and remove partial files
sort $output_dir/maxDeltaUV_*.tmp >> $max_output 2> /dev/null
sort $output_dir/bad_micrographs_*.tmp >> $bad_output 2> /dev/null
rm $output_dir/maxDeltaUV_*.tmp 2> /dev/null
rm $output_dir/bad_micrographs_*.tmp 2> /dev/null




####################################################################################################
### 08. Create pdf report                                                                        ###
####################################################################################################

if [ $(wc -l < $max_output) -gt 2 ] ; then					# there are some datapoints for plotting 
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
### 09. Replace raw defocus values with local values and create new particles star file          ###
####################################################################################################

if [ -s $bad_output ]; then						# file exists and is not empty -> skip 'bad' images and print warning
    while read line; do
	echo -n ""
	mv $output_dir/$subdir/${line%.*}_local.star $output_dir/$subdir/${line%.*}_local.star.bad > /dev/null 2>&1 
	mv $output_dir/$subdir/${line%.*}_gctf.log $output_dir/$subdir/${line%.*}_gctf.log.bad > /dev/null 2>&1 
	mv $output_dir/$subdir/${line%.*}_deltaUV.dat $output_dir/$subdir/${line%.*}_deltaUV.dat.bad > /dev/null 2>&1 # TODO: this line can be most likely removed -> if there were errors, no deltaUV file was created...
    done < $bad_output
    number_of_bad_files=$(wc -l < $bad_output)
    echo "WARNING: $number_of_bad_files files were not processed properly by Gctf (see $bad_output for full list)." 1>&2
    echo "You may want to check what went wrong and run this script again to reprocess these files." 1>&2
    echo "particles_localUVA.star will contain only particles from properly processed images!" 1>&2
else
    echo "Gctf processed all files succesfully!"
fi

echo "Running star_replace_UVA_MCC.com script (by Kai Zhang, modified by MCC)..."
star_replace "$particles_global" "$particles_local" "$output_dir/$subdir/*_local.star"

echo "All done, quitting..."

echo "data_output_nodes" > $output_dir/RELION_OUTPUT_NODES.star
echo "loop_" >> $output_dir/RELION_OUTPUT_NODES.star
echo "_rlnPipeLineNodeName #1" >> $output_dir/RELION_OUTPUT_NODES.star
echo "_rlnPipeLineNodeType #2" >> $output_dir/RELION_OUTPUT_NODES.star
echo "$particles_local 3" >> $output_dir/RELION_OUTPUT_NODES.star
echo "$output_dir/logfile.pdf 13" >> $output_dir/RELION_OUTPUT_NODES.star


touch $output_dir/RELION_JOB_EXIT_SUCCESS
