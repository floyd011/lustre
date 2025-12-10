#!/bin/bash

# Definisanje korisnika
USER=$1
SIZE=+$2
# Prvo, preuzimanje liste foldera u /lustre/fmle_trainings/datasets koje poseduje $USER
folders=$(sudo ls -l /lustre/fmle_trainings/datasets | awk -v user="$USER" '$1 ~ /^d/ && $3 == user {print "/lustre/fmle_trainings/datasets/" $NF}')


function search_large_files() {
    local folder="$1"
    local HEADER_SHOWN=0
    
    # Direktno sortiranje po veličini bez du
    sudo lfs find "$folder" -u "$USER" -type f -s "$SIZE" 2>/dev/null | \
        while IFS= read -r file; do
            if [[ $HEADER_SHOWN -eq 0 ]]; then
                echo "FOLDER: $folder"  >&2
                HEADER_SHOWN=1
            fi
            size=$(sudo ls -l "$file" 2>/dev/null | awk '{print $5}')
            echo "$size $file"
        done | sort -k1 -nr | head -10 | \
        while read -r size file; do
            # Formatiranje veličine
            if [[ $size -ge 1000000000000 ]]; then
                printf "     - %.1fT %s\n" $(echo "scale=1; $size/1000000000000" | bc) "$file"
            elif [[ $size -ge 1000000000 ]]; then
                printf "     - %.1fG %s\n" $(echo "scale=1; $size/1000000000" | bc) "$file"
            elif [[ $size -ge 1000000 ]]; then
                printf "     - %.1fM %s\n" $(echo "scale=1; $size/1000000" | bc) "$file"
            else
                printf "     - %s %s\n" "$size" "$file"
            fi
        done

   if [[ $HEADER_SHOWN -eq 1 ]]; then
      echo
   fi
}


echo "Listing za korisnika $1"
# Prolazak kroz sve foldere iz prve liste
if [ -n "$folders" ]; then
    while IFS= read -r folder; do
        search_large_files "$folder"
    done <<< "$folders"
else
    echo "Nema foldera za korisnika $USER u /lustre/fmle_trainings/datasets"
    echo
fi

# Zatim pretraga u /lustre/data/$USER
folder2="/lustre/data/$USER"
if [ -d "$folder2" ]; then
    search_large_files "$folder2"
else
    echo "Folder $folder2 ne postoji."
fi
