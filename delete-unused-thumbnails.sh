#!/bin/bash
#-q | --quiet	- >		suppress file deletion output
#Compatible with Freedesktop.org (GTK) and KDE thumbnail standards

thumbnail_cache_directory="$HOME/.cache/thumbnails"
log_file="$HOME/.cache/thumbnails/delete_used_thumbnail.log"
deleted=0
total_thumbnails=0
quiet=false

if [[ "$1" == "-q" || "$1" == "--quiet" ]]; then
    quiet=true
fi

timestamp() {
	echo "$(date '+%Y-%m-%d %H:%M:%S')"
}

#Prevents the literal *.png from being read.
shopt -s nullglob

for size in fail normal large x-large xx-large ; do
	thumbs=( "$thumbnail_cache_directory/$size"/*.png )
	
	#If there are no thumbnails in the directory, then skip to the next directory
	if [[ ${#thumbs[@]} -eq 0 ]]; then
		continue
	fi
	
	#Adds the total amount of thumbnail files across all five directories
	total_thumbnails=$(( total_thumbnails + ${#thumbs[@]} ))

    while IFS='|' read -r fname uri; do
		thumb="$thumbnail_cache_directory/$size/$fname"
		
		#If thumbnail disappeared before processing then skip 
		if [[ ! -f $thumb ]]; then
			echo "Warning: thumbnail vanished before processing: $thumb" >&2
			continue
		fi

		#If exiftool printed no ThumbURI then log and skip
		if [[ -z $uri ]]; then
			echo "[$(timestamp)] ERROR: Thumbnail ($thumb) metadata does not contain ThumbURI," | tee -a "$log_file"
			continue
		fi

		#If ThumbURI does not begin with file:///, checks to see if it begins with "trash//" otherwise skip and log
		if [[ $uri != file://* ]]; then
			if [[ $uri == trash://* ]]; then
				echo "Deleting thumbnail for trash file: $uri"
				echo "  -> thumbnail: $thumb"
				rm -f -- "$thumb" && ((deleted++))		
			else
				echo "[$(timestamp)] ERROR: ThumbURI for $thumb is $uri and does not begin with 'file://' or 'trash://'," | tee -a "$log_file"
			fi
			continue	
		fi
						  
		#Removes the "file://" prefix
		unix_path="${uri#file://}"	
		#Replaces any "%" with "\x" which prepares the string for printf (%20 -> \x20)
		unix_path="${unix_path//%/\\x}"
		#Converts the unicode (eg. "%20" -> " ") so the filesystem can read it properly and match the filename
		printf -v file_path "$unix_path"

		#Checks to see if the original files exists, if not delete the thumbnail
		if [[ ! -e $file_path ]]; then
			rm -f -- "$thumb"
			deleted=$((deleted + 1))
			
			if ! $quiet; then
				echo "Deleting thumbnail for missing file: $file_path"
				echo "  -> thumbnail: $thumb"
			fi
		fi
	#Calling exiftool in batches ensures that the number of characters in a shell doesn't exceed the limit. Using a text file to feed exiftool the thumbnails overloads exiftool and results in *much* worse performance if processing tens of thousands of thumbnails.
  #Calling exiftool for every file also results in much worse performance. 1000 per batch seems to be close for optimal performance
	#Exiftool needs to be called with its full path because cron only has a $PATH of /bin and /usr/bin
	#Suppresses warning "Trailer data after PNG IEND chunk". This trailer data is used in another script to mark compressed pngs.
	#For whatever dumb reason exiftool needs to be called with "-q -q" and not "-qq" to actually suppress the output.
	done < <(printf '%s\0' "${thumbs[@]}" | xargs -0 --max-args=1000 --max-chars=2000000 /usr/bin/vendor_perl/exiftool -q -q -s3 -p '$FileName|$ThumbURI' 2> >(grep -vF 'Trailer data after PNG IEND chunk' >&2))
done

echo "[$(timestamp)] Scanned $total_thumbnails thumbnails. Deleted $deleted orphaned thumbnails." | tee -a "$log_file"
