#!/bin/bash
# Generiše Lustre metrike u Prometheus formatu za node_exporter textfile collector
# Koristi lfs find za dobijanje liste korisnika

set -o pipefail
IFS=$'\n\t'

# Konfiguracija
METRICS_DIR="/home/mspasic/lustre_exporter/exporter"
METRICS_FILE="$METRICS_DIR/lustre.prom"
LOCK_FILE="/tmp/lustre_metrics.lock"
MOUNT_POINT="/lustre"
HOME_POINT="/home"
DATA_PATH="/lustre/data"  # Putanja gde se nalaze korisnički direktorijumi

get_lustre_users() {
    local users=""
    
    # Prvi pokušaj: lfs find za direktorijume korisnika
    if [ -d "$DATA_PATH" ]; then
        # Dobij sve direktorijume prvog nivoa u DATA_PATH (pretpostavka da su korisnici)
        users=$(sudo lfs find "$DATA_PATH" -maxdepth 1 -type d 2>/dev/null | \
                awk -F/ 'NF>3 && $0 != "'"$DATA_PATH"'" {print $NF}' | \
                sort | uniq)
    fi
    
    # Ako nema korisnika, probaj sa glavnim mount point-om
    if [ -z "$users" ] && [ -d "$MOUNT_POINT" ]; then
        users=$(sudo lfs find "$MOUNT_POINT" -maxdepth 1 -type d 2>/dev/null | \
                awk -F/ 'NF>3 && $0 != "'"$MOUNT_POINT"'" {print $NF}' | \
                sort | uniq)
    fi
    
    echo "$users"
}

# Poboljšana human_to_bytes funkcija koja radi sa .prom
human_to_bytes_improved() {
    local size="$1"
    
    # Ukloni zareze
    size=$(echo "$size" | tr -d ',')
    
    # Proveri da li je već u bajtovima (bez slova)
    if [[ "$size" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "$size" | awk '{printf "%.0f", $1}'
        return
    fi
    
    # Ekstraktuj broj i jedinicu
    local num=$(echo "$size" | sed 's/[^0-9.]//g')
    local unit=$(echo "$size" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
    
    case $unit in
        "T"|"TB") echo "$num * 1099511627776" | bc | awk '{printf "%.0f", $1}';;
        "G"|"GB") echo "$num * 1073741824" | bc | awk '{printf "%.0f", $1}';;
        "M"|"MB") echo "$num * 1048576" | bc | awk '{printf "%.0f", $1}';;
        "K"|"KB") echo "$num * 1024" | bc | awk '{printf "%.0f", $1}';;
        "B") echo "$num" | awk '{printf "%.0f", $1}';;
        *) echo "0" ;;
    esac
}

# Parsiraj lfs quota -hu output
parse_quota_output() {
    local output="$1"
    local user="$2"
    local mp="$3"
    
    echo "$output" | while IFS= read -r line; do
        # Debug: prikaži svaku liniju
        # echo "DEBUG: Procesiram liniju: '$line'" >&2
        
        # Traži liniju sa podacima - popravljen regex
        # Format: /lustre  54.01G      0k      0k
        # Ili:    /mnt/lustre  1.5T   500G   1.0T
        if [[ "$line" =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]+([0-9.]+[TGMK]?[B]?)[[:space:]]+([0-9.]+[TGMK]?[B]?)[[:space:]]+([0-9.]+[TGMK]?[B]?) ]]; then
            fs="${BASH_REMATCH[1]}"
            usage_str="${BASH_REMATCH[2]}"
            soft_str="${BASH_REMATCH[3]}"
            hard_str="${BASH_REMATCH[4]}"
            
            # Debug
            # echo "DEBUG: Pronadjeno - FS: $fs, Used: $usage_str, Soft: $soft_str, Hard: $hard_str" >&2
            
            # Proveri da li se filesystem poklapa (možda bez leading /)
            if [[ "$fs" != "$mp" ]] && [[ "$fs" != "${mp#/}" ]]; then
                # Ako nije naš filesystem, preskoči
                continue
            fi
            
            # Konvertuj u bajte
            usage_bytes=$(human_to_bytes_improved "$usage_str")
            soft_bytes=$(human_to_bytes_improved "$soft_str")
            hard_bytes=$(human_to_bytes_improved "$hard_str")
            
            # Debug konverzije
            # echo "DEBUG: Konvertovano - Used: $usage_bytes, Soft: $soft_bytes, Hard: $hard_bytes" >&2
            
            # Ispiši metrike samo ako imamo validne podatke
            if [ "$usage_bytes" -ge 0 ] 2>/dev/null; then
                echo "lustre_quota_usage_bytes{user=\"$user\",filesystem=\"$mp\"} $usage_bytes"
                [ "$soft_bytes" -ge 0 ] 2>/dev/null && \
                echo "lustre_quota_soft_limit_bytes{user=\"$user\",filesystem=\"$mp\"} $soft_bytes"
                [ "$hard_bytes" -ge 0 ] 2>/dev/null && \
                echo "lustre_quota_hard_limit_bytes{user=\"$user\",filesystem=\"$mp\"} $hard_bytes"
            fi
        # Alternativni regex za format sa "k" (kilobajti) kao u tvom primeru
        elif [[ "$line" =~ ^[[:space:]]*([^[:space:]]+)[[:space:]]+([0-9.]+[TGMK]?[B]?)[[:space:]]+([0-9.]+[k]?)[[:space:]]+([0-9.]+[k]?) ]]; then
            fs="${BASH_REMATCH[1]}"
            usage_str="${BASH_REMATCH[2]}"
            soft_str="${BASH_REMATCH[3]}"
            hard_str="${BASH_REMATCH[4]}"
            
            # Debug
            # echo "DEBUG (alt): Pronadjeno - FS: $fs, Used: $usage_str, Soft: $soft_str, Hard: $hard_str" >&2
            
            if [[ "$fs" != "$mp" ]] && [[ "$fs" != "${mp#/}" ]]; then
                continue
            fi
            
            usage_bytes=$(human_to_bytes_improved "$usage_str")
            # Za "k" pretpostavljamo da su kilobajti
            soft_bytes=$(echo "$soft_str" | sed 's/k//' | awk '{print $1 * 1024}')
            hard_bytes=$(echo "$hard_str" | sed 's/k//' | awk '{print $1 * 1024}')
            
            if [ "$usage_bytes" -ge 0 ] 2>/dev/null; then
                echo "lustre_quota_usage_bytes{user=\"$user\",filesystem=\"$mp\"} $usage_bytes"
                [ "$soft_bytes" -ge 0 ] 2>/dev/null && \
                echo "lustre_quota_soft_limit_bytes{user=\"$user\",filesystem=\"$mp\"} $soft_bytes"
                [ "$hard_bytes" -ge 0 ] 2>/dev/null && \
                echo "lustre_quota_hard_limit_bytes{user=\"$user\",filesystem=\"$mp\"} $hard_bytes"
            fi
        fi
    done
}

# Funkcija za generisanje metrika
generate_metrics() {
    # Kreiraj privremeni fajl
    local temp_file=$(mktemp)
    local user_count=0
    local error_count=0
    
    # 1. Filesystem metrike koristeći lfs df
    {
        echo "# HELP lustre_filesystem_capacity_bytes Total capacity of Lustre filesystem"
        echo "# TYPE lustre_filesystem_capacity_bytes gauge"
        echo "# HELP lustre_filesystem_used_bytes Used space on Lustre filesystem"
        echo "# TYPE lustre_filesystem_used_bytes gauge"
        
        if command -v lfs &> /dev/null && [ -d "$MOUNT_POINT" ]; then
            # Koristi lfs df za tačnije podatke
            lfs df "$MOUNT_POINT" | awk -v mp="$MOUNT_POINT" '
            /filesystem_summary:/ {
                total_kb = $2
                used_kb = $3
                total_bytes = total_kb * 1024
                used_bytes = used_kb * 1024
                
                print "lustre_filesystem_capacity_bytes{filesystem=\"" mp "\"} " total_bytes
                print "lustre_filesystem_used_bytes{filesystem=\"" mp "\"} " used_bytes
            }'
        fi

        echo "# HELP filesystem_capacity_bytes Total capacity of filesystem"
        echo "# TYPE filesystem_capacity_bytes gauge"
        echo "# HELP filesystem_used_bytes Used space on filesystem"
        echo "# TYPE filesystem_used_bytes gauge"
        
        if command -v df &> /dev/null && [ -d "$HOME_POINT" ]; then
            # Koristi lfs df za tačnije podatke
            df "$HOME_POINT" | awk -v mp="$HOME_POINT" '
            /master:\/home/ {
                total_kb = $2
                used_kb = $3
                total_bytes = total_kb * 1024
                used_bytes = used_kb * 1024
                
                print "filesystem_capacity_bytes{filesystem=\"" mp "\"} " total_bytes
                print "filesystem_used_bytes{filesystem=\"" mp "\"} " used_bytes
            }'
        fi
    } >> "$temp_file"

    # 2. User quota metrike
    {
        echo "# HELP lustre_quota_usage_bytes User quota usage in bytes"
        echo "# TYPE lustre_quota_usage_bytes gauge"
        echo "# HELP lustre_quota_soft_limit_bytes User soft quota limit in bytes"
        echo "# TYPE lustre_quota_soft_limit_bytes gauge"
        echo "# HELP lustre_quota_hard_limit_bytes User hard quota limit in bytes"
        echo "# TYPE lustre_quota_hard_limit_bytes gauge"
        
        if command -v lfs &> /dev/null && [ -d "$MOUNT_POINT" ]; then
            # Dobij listu korisnika
            users=$(get_lustre_users)
            
            if [ -n "$users" ]; then
                echo "# INFO: Pronađeno $(echo "$users" | wc -l) korisnika" >> "$temp_file"
                
                # Procesiraj svakog korisnika
                while IFS= read -r user; do
                    # Preskoči prazne linije i specijalne direktorijume
                    [[ -z "$user" ]] && continue
                    [[ "$user" == "lost+found" ]] && continue
                    [[ "$user" == "." ]] && continue
                    [[ "$user" == ".." ]] && continue
                    output=$(sudo lfs quota -hu "$user" "$MOUNT_POINT" 2>&1)
                    exit_code=$?
                    if [[ $exit_code -eq 0 ]] && [[ "$output" == *"Disk quotas for usr"* ]]; then
                    
                        # Uzmi kvotu za korisnika
                        quota_output=$(sudo lfs quota -hu "$user" "$MOUNT_POINT" 2>/dev/null)
    
                        if [ $? -eq 0 ] && [ -n "$quota_output" ]; then
                            # Parsiraj izlaz
                            parse_quota_output "$quota_output" "$user" "$MOUNT_POINT"
                            ((user_count++))
                        fi
                    fi
                    # Ograniči na 1000 korisnika maksimalno (radi performansi)
                    if [ $user_count -ge 1000 ]; then
                        echo "# WARNING: Dostignut limit od 1000 korisnika, prekidam..." >> "$temp_file"
                        break
                    fi
                    
                done <<< "$users"
            else
                echo "# WARNING: Nema pronađenih korisnika" >> "$temp_file"
            fi
        fi
    } >> "$temp_file"
    
    # 3. Dodatne metrike
    {
        # Timestamp metrika
        echo "# HELP lustre_metrics_last_scrape Timestamp of last metrics scrape"
        echo "# TYPE lustre_metrics_last_scrape gauge"
        echo "lustre_metrics_last_scrape $(date +%s)"
        
        # Error metrika
        echo "# HELP lustre_metrics_errors Number of errors during metrics collection"
        echo "# TYPE lustre_metrics_errors counter"
        echo "lustre_metrics_errors $error_count"
        
        # User count metrika
        echo "# HELP lustre_users_count Number of users with quotas"
        echo "# TYPE lustre_users_count gauge"
        echo "lustre_users_count $user_count"
        
        # Filesystem info metrika
        echo "# HELP lustre_filesystem_info Lustre filesystem information"
        echo "# TYPE lustre_filesystem_info gauge"
        echo "lustre_filesystem_info{filesystem=\"$MOUNT_POINT\",data_path=\"$DATA_PATH\"} 1"
    } >> "$temp_file"
    
    # Premesti temp fajl na konačnu lokaciju
    mv "$temp_file" "$METRICS_FILE"
    
    # Podesi permisije
    chmod 644 "$METRICS_FILE"
    
    echo "Generisano metrika za $user_count korisnika, grešaka: $error_count"
}

# Main
main() {
    # Kreiraj direktorijum ako ne postoji
    mkdir -p "$METRICS_DIR"
    
    # Generiši metrike
    generate_metrics
    
    echo "Metrike su generisane u $METRICS_FILE"
}

# Pokreni
main "$@"
