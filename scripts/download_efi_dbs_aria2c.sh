#!/bin/bash

# Set default values
RESUME_MODE=false
VERBOSE=false
CONNECTIONS=8  # Number of parallel connections per file

# Function to log messages with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if aria2c is installed
check_aria2c() {
    if ! command -v aria2c &> /dev/null; then
        log_message "ERROR: aria2c is not installed"
        log_message "Install with: sudo apt-get install aria2 (Ubuntu/Debian) or sudo yum install aria2 (CentOS/RHEL)"
        exit 1
    fi
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

# Robust aria2c download function
robust_aria2c_download() {
    local url="$1"
    local output_dir="$2"
    local output_file="$3"
    local description="$4"
    
    log_message "Starting download: $description"
    log_message "URL: $url"
    log_message "Output: $output_dir/$output_file"
    
    # Create output directory if it doesn't exist
    mkdir -p "$output_dir"
    
    # aria2c with optimal settings for large files
    if aria2c \
        --continue=true \
        --max-tries=10 \
        --retry-wait=30 \
        --timeout=60 \
        --max-connection-per-server="$CONNECTIONS" \
        --split="$CONNECTIONS" \
        --min-split-size=10M \
        --file-allocation=falloc \
        --check-integrity=true \
        --summary-interval=30 \
        --download-result=full \
        --dir="$output_dir" \
        --out="$output_file" \
        "$url"; then
        log_message "Successfully downloaded: $description"
        return 0
    else
        log_message "ERROR: Failed to download: $description"
        return 1
    fi
}

# Function to extract with verification
extract_and_verify() {
    local file="$1"
    local dir="$2"
    local extract_type="$3"
    local description="$4"
    
    log_message "Extracting: $description"
    
    case $extract_type in
        "tar")
            # Test archive integrity first
            if ! tar -tzf "$file" >/dev/null 2>&1; then
                log_message "ERROR: Archive $file appears to be corrupted"
                return 1
            fi
            
            if tar xzf "$file" -C "$dir"; then
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
            if ! gunzip -t "$file" 2>/dev/null; then
                log_message "ERROR: Gzip file $file appears to be corrupted"
                return 1
            fi
            
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

# Function to check if database already exists
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
        echo "Usage: bash scripts/download_efi_dbs.sh [OPTIONS]

    Description:
        Download the required EFI Databases using aria2c for maximum speed and reliability.
        Optimized for large (1TB+) downloads with automatic resume and parallel connections.

    Options:
        --data-dir       path to the test dataset; default: ./data/efi
        --source-url     a URL web address from which the databases will be sourced
                        default: https://efi.igb.illinois.edu/downloads/databases/latest
        --connections    number of parallel connections per file; default: 8
        --resume         skip downloading databases that already exist; default: false
        --verbose        enable verbose logging; default: false
        --help           prints this message

    Features:
        - Automatic resume of interrupted downloads
        - Parallel downloading with multiple connections
        - Built-in integrity checking
        - Real-time progress bars with speed and ETA
        - Robust retry logic (10 attempts)
        - Disk space verification before starting

    Examples:
        bash scripts/download_efi_dbs.sh --data-dir scratch/efi/ip104 --source-url https://efi.igb.illinois.edu/downloads/databases/20250210/
        bash scripts/download_efi_dbs.sh --resume --connections 16 --verbose
"
        exit 0
    elif [[ ${!index} == "--data-dir" ]]; then
        DIR="${!idx}"
    elif [[ ${!index} == "--source-url" ]]; then
        remote_base="${!idx}"
    elif [[ ${!index} == "--connections" ]]; then
        CONNECTIONS="${!idx}"
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

# Check if aria2c is installed
check_aria2c

log_message "=== EFI Database Download (aria2c-based) ==="
log_message "Source URL: $remote_base"
log_message "Output directory: $DIR"
log_message "Parallel connections: $CONNECTIONS"
log_message "Resume mode: $RESUME_MODE"

# Check disk space (estimate 1TB requirement)
check_disk_space "$DIR" 1100

# Create output directory
mkdir -p "$DIR"

# Function to build URL correctly (handles trailing slashes)
build_url() {
    local base="$1"
    local path="$2"
    # Remove trailing slash from base if it exists
    base="${base%/}"
    # Remove leading slash from path if it exists
    path="${path#/}"
    echo "$base/$path"
}

# Download and extract BLAST database (exactly like original)
log_message "=== Processing BLAST Database ==="
if [[ "$RESUME_MODE" == true ]] && check_existing_db "$DIR" "blast"; then
    log_message "BLAST database already exists, skipping..."
else
    file="blastdb.tar.gz"
    blast_url=$(build_url "$remote_base" "blastdb/$file")
    
    if robust_aria2c_download "$blast_url" "$DIR" "$file" "BLAST Database"; then
        if extract_and_verify "$DIR/$file" "$DIR" "tar" "BLAST Database"; then
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

# Download and extract DIAMOND database (exactly like original)
log_message "=== Processing DIAMOND Database ==="
if [[ "$RESUME_MODE" == true ]] && check_existing_db "$DIR" "diamond"; then
    log_message "DIAMOND database already exists, skipping..."
else
    file="diamonddb.tar.gz"
    diamond_url=$(build_url "$remote_base" "diamonddb/$file")
    
    if robust_aria2c_download "$diamond_url" "$DIR" "$file" "DIAMOND Database"; then
        if extract_and_verify "$DIR/$file" "$DIR" "tar" "DIAMOND Database"; then
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

# Download and decompress EFI DB SQLite file (exactly like original)
log_message "=== Processing EFI SQLite Database ==="
if [[ "$RESUME_MODE" == true ]] && check_existing_db "$DIR" "efi"; then
    log_message "EFI SQLite database already exists, skipping..."
else
    file="efi_db.sqlite.gz"
    efi_url=$(build_url "$remote_base" "efi_db/$file")
    
    if robust_aria2c_download "$efi_url" "$DIR" "$file" "EFI SQLite Database"; then
        if extract_and_verify "$DIR/$file" "$DIR" "gunzip" "EFI SQLite Database"; then
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
