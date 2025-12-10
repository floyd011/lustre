#!/bin/bash
LUSTRE_FS="/lustre"

extract_num() {
    echo "$1" | sed -E 's/([0-9]+(\.[0-9]+)?).*/\1/'
}

extract_unit() {
    echo "$1" | sed -E 's/.*([TGMk])$/\1/'
}

unit_priority() {
    case "$1" in
        T) echo 4 ;;
        G) echo 3 ;;
        M) echo 2 ;;
        k) echo 1 ;;
        *) echo 0 ;;
    esac
}
echo "                              Filesystem    used   quota   limit   grace   files   quota   limit   grace"
while IFS= read -r line; do
    # KORIGOVANO: sada je treća kolona veličina!
    size=$(echo "$line" | awk '{print $3}')

    num=$(extract_num "$size")
    unit=$(extract_unit "$size")
    prio=$(unit_priority "$unit")

    # Čuvamo format za sortiranje:
    # PRIORITET NUMERIKA ORIGINALNI_RED
    echo "$prio $num $line"
done < <(# 1. prvo prikupimo sve parove u privremenu listu
declare -a users
declare -a data

prev_user=""

while IFS= read -r line; do

    # Prvi red: Disk quotas for usr USER...
    if [[ "$line" =~ ^Disk\ quotas\ for\ usr ]]; then
        # Izvuci korisnika - sve između "usr " i " (uid"
        user=$(echo "$line" | sed -E 's/^Disk quotas for usr ([^ ]+).*/\1/')
        prev_user="$user"
        continue
    fi

    # Drugi red: /lustre ...
    if [[ "$line" =~ /lustre ]]; then
        # Očisti leading whitespace i ostavi samo od /lustre nadalje
        clean=$(echo "$line" | sed -E 's/^[[:space:]]+//')
        users+=("$prev_user")
        data+=("$clean")
        prev_user=""
    fi

done < <(while read -r USERNAME; do
             [[ -z "$USERNAME" ]] || [[ "$USERNAME" == "data" ]] && continue
    
             lfs quota -hu "$USERNAME" "$LUSTRE_FS" 2>/dev/null 
    
         done < <(lfs find /lustre/data -maxdepth 1 -type d | awk -F/ 'NF>3 && $0 != "/lustre/data" {print $NF}') | grep -v -e "using default file quota setting" -e "using default block quota setting" -e "is using default is using default" -e "Filesystem    used   quota   limit   grace   files   quota   limit   grace" )

# 2. Nađi maksimalnu dužinu korisničkog imena
maxlen=0
for u in "${users[@]}"; do
    len=${#u}
    (( len > maxlen )) && maxlen=$len
done

# 3. Ispiši formatirano
for i in "${!users[@]}"; do
    printf "%-${maxlen}s  %s\n" "${users[$i]}" "${data[$i]}"
done) | sort -k1,1nr -k2,2nr | cut -d' ' -f3-



