#!/bin/bash
while read -r USERNAME; do
             [[ -z "$USERNAME" ]] || [[ "$USERNAME" == "data" ]] && continue
    
             lfs setquota -u "$USERNAME" --block-softlimit 1024G --block-hardlimit 0 /lustre    
done < <(lfs find /lustre/data -maxdepth 1 -type d | awk -F/ 'NF>3 && $0 != "/lustre/data" {print $NF}') 
