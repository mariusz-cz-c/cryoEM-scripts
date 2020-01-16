#!/bin/bash

# This function monitors the progress of some process that is generating output files that can be counted
# usage: progress folder=$1 search_pattern=$2 MAX_NUMBER=$3 SKIP_FILES=${4:-0}
# optional modifier 1: progress_sleep_time=n (refresh progress bar every n seconds, default 1)
# optional modifier 2: unset=false (true or false, default false)
progress(){
	local folder=$1								# $1 -> search folder
	local search_pattern=$2							# $2 -> search pattern inside search folder
	local MAX_NUMBER=$3							# $3 -> number of files to be processed
	local SKIP_FILES=${4:-0}						# $4 -> number of files to be skipped (or default = 0)
	local sleep_time=${progress_sleep_time:-1}				# sleep time (default=1, can be set via $progress_sleep_time variable)
	local unset=${progress_unset:-false}					# clear progress bar after finished (default=false, can be set via $progress_unset variable)
	local line1="--------------------------------------------------"	# empty bar
	local line2="=================================================>"	# filled bar
	local counter								# number of processed files
	local frac								# fraction of processed files
	local percent								# percent of processed files
	local duration								# duration of script
	local end_text								# what should be printed upon exit depending on $unset
	local terminate=false							# terminate if true
	trap "{ terminate=true; }" SIGINT SIGTERM				# display last repetition and stop loop when killed
	if [ "$unset" = true ]; then
	    end_text="\033[2K\033[0A\033[2K\r"					# clear last two lines
	else
	    end_text="\n"							# go to next line
	fi
	SECONDS=0								# timer for ETA
	if [ "$MAX_NUMBER" = 0 ]; then exit; fi
	while true
	do
		counter=$(find $folder -type f ! -empty -name "$search_pattern" | wc -l)		# this counts only non-empty files!
		counter=$((counter-SKIP_FILES)) 						# skip $SKIP_FILES files
		frac=$((50*counter/MAX_NUMBER))							# int fraction (x/50)
		percent=$(bc <<< "scale=2; 100*$counter/$MAX_NUMBER")				# float percent progress
		duration=$SECONDS								# total time of processing
		time=$(TZ=UTC0 printf "%(%H:%M:%S)T" "$duration")				# total time as string
		if [ "$duration" -gt "0" ] && [ "$counter" != "0" ]; then			#   ETA =  (total-processed) * (duration/processed)
		    ETA=$(TZ=UTC0 printf "%(%H:%M:%S)T" "$(( (MAX_NUMBER-counter) * duration/counter ))" )
		fi
		LC_NUMERIC=C printf "\033[0KProgress: [%s%s] %6.2f%%\n" "${line2:(50-$frac)}" "${line1:($frac)}" $percent	
									# LC_NUMERIC=C for proper interpretation of ',' decimal separator
		printf "%-40s time: %s  ETA: %s" "$counter out of $MAX_NUMBER files processed" "$time" "${ETA:="N/A"}"
		if [ "$terminate" = true ]; 		then printf "$end_text"; break; fi	# quit if killed
		if [ "$counter" = $MAX_NUMBER ]; 	then printf "$end_text"; break; fi	# quit if finished and not killed
		sleep $sleep_time								# sleep 
		printf "\033[1A\r"								# clear counter
	done
	exit
}




# based on:
# https://stackoverflow.com/questions/3231804/in-bash-how-to-add-are-you-sure-y-n-to-any-command-or-alias
# usage1: confirm && echo "confirmed..." || exit
# usage2: confirm "Are you sure?" && echo "confirmed..." || exit
# usage3: confirm "Is this proper value?" && : || angpix=$(read_input_float "pixel size (Angstrom)" $angpix) 
confirm() {
    # call with a prompt string or use a default
    read -r -p "${1:-Do you want to continue?} [y/n] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}




# This function reads user input (FLOAT) with provided querry $1 and  (optional) default value $2
read_input_float(){							#$1 -> text, $2 -> default value
    local text=$1
    local default_value=$2
    local value=""
    is_float="^([0-9]*[.])?[0-9]+$"					# only positive numbers allowed; for +/- use "^[+-]?([0-9]*[.])?[0-9]+$"
    if [ "$default_value" = "" ]; then 
        local querry=" -> $1: "
    else
	local querry=" -> $1 [default: $2]: "
    fi
    while [[ ! ${value} =~ $is_float ]]; do
        read -p "$querry" value 
        if [ "$value" = "" ]; then value=$default_value; fi
    done
    echo $value
}

