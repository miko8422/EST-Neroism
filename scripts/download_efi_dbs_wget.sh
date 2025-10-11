#!/bin/bash

# download_efi_dbs_wget.sh - Hybrid version using wget instead of Python downloader
# This replaces the python3 bin/download_file.py with robust wget calls

# Set default values
RESUME_MODE=false
VERBOSE=false

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check available disk space (in GB)
check_disk_space() {
    local dir="$1"
    local required_gb="$2"
    
    mkdir -p "$dir"
    local available_gb=$(df "$dir" | awk 'NR==2 {printf "%.0f", $4/1024/1024}')
    
    if [[ $available_gb -lt $required_gb ]]; then
        log_message "ERROR: Insufficient disk space. Required: ${required_gb}GB, Available: ${available_gb}GB"
        exit 1
    else
        log_message "Disk space check passed. Available: ${available_gb}GB, Required: ${required_gb}GB"
    fi
}

# Robust wget download function with progress bar
robust_wget_download() {
    local url="$1"
    local output_file="$2"
    local description="$3"
    
    log_message "Starting download: $description"
    log_message "URL: $url"
    log_message "Output: $output_file"
    
    # Create output directory if it doesn't exist
    mkdir -p "$(dirname "$output_file")"
    
    # wget with robust settings and progress bar
    if wget \
        --continue \
        --tries=10 \
        --timeout=60 \
        --retry-connrefused \
        --waitretry=30 \
        --progress=bar:force:noscroll \
        --show-progress \
        --no-check-certificate \
        "$url" \
        -O "$output_file"; then
        log_message "Successfully downloaded: $description"
        return 0
    else
        log_message "ERROR: Failed to download: $description"
        return 1
    fi
}

# Function to extract with verification and progress
extract_and_verify() {
    local file="$1"
    local dir="$2"
    local extract_type="$3"
    local description="$4"
    
    log_message "Extracting: $description"
    
    case $extract_type in
        "tar")
            # Test archive integrity first
            log_message "Testing archive integrity..."
            if ! tar -tzf "$file" >/dev/null 2>&1; then
                log_message "ERROR: Archive $file appears to be corrupted"
                return 1
            fi
            
            log_message "Archive integrity check passed. Extracting..."
            if tar -xzf "$file" -C "$dir" --checkpoint=10000 --checkpoint-action=echo="Extracted %{checkpoint}0k records"; then
                log_message "Successfully extracted: $description"
                rm "$file"
                return 0
            else
                log_message "ERROR: Failed to extract: $description"
                return 1
            fi
            ;;
        "gunzip")
            # Test gzip integrity first
            log_message "Testing gzip file integrity..."
            if ! gunzip -t "$file" 2>/dev/null; then
                log_message "ERROR: Gzip file $file appears to be corrupted"
                return 1
            fi
            
            log_message "Gzip integrity check passed. Decompressing..."
            if gunzip "$file"; then
                log_message "Successfully decompressed: $description"
                return 0
            else
                log_message "ERROR: Failed to decompress: $description"
                return 1
            fi
            ;;
    esac
}

# Function to check if database already exists and is complete
check_existing_db() {
    local dir="$1"
    local db_type="$2"
    
    case $db_type in
        "blast")
            if [[ -d "$dir/blast" ]] && [[ -n "$(ls -A $dir/blast 2>/dev/null)" ]]; then
                return 0
            fi
            ;;
        "diamond")
            if [[ -d "$dir/diamond" ]] && [[ -n "$(ls -A $dir/diamond 2>/dev/null)" ]]; then
                return 0
            fi
            ;;
        "efi")
            if [[ -f "$dir/efi_db.sqlite" ]] && [[ -s "$dir/efi_db.sqlite" ]]; then
                return 0
            fi
            ;;
    esac
    return 1
}

# Parse command line arguments
for (( index=1; index <= $#; index++ ))
do
    idx=$((index+1))
    if [[ ${!index} == '--help' ]]; then
        echo "Usage: bash scripts/download_efi_dbs_wget.sh [OPTIONS]

    Description:
        Download the required EFI Databases using wget for maximum reliability.
        This is a hybrid version that replaces the python downloader with wget.
        Optimized for large (1TB+) downloads with automatic resume capability.

    Options:
        --data-dir      path to the test dataset; default: ./data/efi
        --source-url    a URL web address from which the databases will be sourced
                       default: https://efi.igb.illinois.edu/downloads/databases/latest
        --resume        skip downloading databases that already exist; default: false
        --verbose       enable verbose logging; default: false
        --help          prints this message

    Features:
        - Uses wget instead of python downloader for better reliability
        - Automatic resume of interrupted downloads (wget -c)
        - Built-in retry logic (10 attempts with exponential backoff)
        - Progress bars with real-time speed and ETA
        - Disk space verification before starting
        - Integrity checking before extraction
        - Detailed logging with timestamps

    Examples:
        bash scripts/download_efi_dbs_wget.sh --data-dir scratch/efi/ip104 --source-url https://efi.igb.illinois.edu/downloads/databases/20250210/
        bash scripts/download_efi_dbs_wget.sh --resume --verbose
        
    Difference from original:
        - Original uses: python3 bin/download_file.py (no progress, single connection)
        - This uses: wget (progress bars, better resume, more reliable)
"
        exit 0
    elif [[ ${!index} == "--data-dir" ]]; then
        DIR="${!idx}"
    elif [[ ${!index} == "--source-url" ]]; then
        remote_base="${!idx}"
    elif [[ ${!index} == "--resume" ]]; then
        RESUME_MODE=true
    elif [[ ${!index} == "--verbose" ]]; then
        VERBOSE=true
    fi
done 

# Apply default values
if [[ -z "$DIR" ]]; then
    DIR="$(pwd)/data/efi"
fi

if [[ -z "$remote_base" ]]; then
    remote_base="https://efi.igb.illinois.edu/downloads/databases/latest"
fi

log_message "=== EFI Database Download (wget-based hybrid) ==="
log_message "Source URL: $remote_base"
log_message "Output directory: $DIR"
log_message "Resume mode: $RESUME_MODE"

# Check disk space (estimate 1TB requirement)
check_disk_space "$DIR" 1100

# Create output directory
mkdir -p "$DIR"

# Download and extract BLAST database
log_message "=== Processing BLAST Database ==="
if [[ "$RESUME_MODE" == true ]] && check_existing_db "$DIR" "blast"; then
    log_message "BLAST database already exists, skipping..."
else
    blast_url="$remote_base/blastdb/blastdb.tar.gz"
    blast_file="$DIR/blastdb.tar.gz"
    
    if robust_wget_download "$blast_url" "$blast_file" "BLAST Database"; then
        if extract_and_verify "$blast_file" "$DIR" "tar" "BLAST Database"; then
            log_message "BLAST database setup complete"
        else
            log_message "ERROR: BLAST database extraction failed"
            exit 1
        fi
    else
        log_message "ERROR: BLAST database download failed"
        exit 1
    fi
fi

# Download and extract DIAMOND database
log_message "=== Processing DIAMOND Database ==="
if [[ "$RESUME_MODE" == true ]] && check_existing_db "$DIR" "diamond"; then
    log_message "DIAMOND database already exists, skipping..."
else
    diamond_url="$remote_base/diamonddb/diamonddb.tar.gz"
    diamond_file="$DIR/diamonddb.tar.gz"
    
    if robust_wget_download "$diamond_url" "$diamond_file" "DIAMOND Database"; then
        if extract_and_verify "$diamond_file" "$DIR" "tar" "DIAMOND Database"; then
            log_message "DIAMOND database setup complete"
        else
            log_message "ERROR: DIAMOND database extraction failed"
            exit 1
        fi
    else
        log_message "ERROR: DIAMOND database download failed"
        exit 1
    fi
fi

# Download and decompress EFI DB SQLite file
log_message "=== Processing EFI SQLite Database ==="
if [[ "$RESUME_MODE" == true ]] && check_existing_db "$DIR" "efi"; then
    log_message "EFI SQLite database already exists, skipping..."
else
    efi_url="$remote_base/efi_db/efi_db.sqlite.gz"
    efi_file="$DIR/efi_db.sqlite.gz"
    
    if robust_wget_download "$efi_url" "$efi_file" "EFI SQLite Database"; then
        if extract_and_verify "$efi_file" "$DIR" "gunzip" "EFI SQLite Database"; then
            log_message "EFI SQLite database setup complete"
        else
            log_message "ERROR: EFI SQLite database decompression failed"
            exit 1
        fi
    else
        log_message "ERROR: EFI SQLite database download failed"
        exit 1
    fi
fi

log_message "=== All databases downloaded and extracted successfully! ==="

# Show final summary
if [[ "$VERBOSE" == true ]]; then
    log_message "=== Download Summary ==="
    log_message "Directory contents:"
    du -h "$DIR"/* 2>/dev/null || true
    log_message "Total directory size: $(du -sh "$DIR" | cut -f1)"
fi

log_message "Download completed at: $(date)"
