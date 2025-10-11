#!/bin/bash

# Configuration
DOWNLOAD_SCRIPT="scripts/download_efi_dbs.sh"
DATA_DIR="./scratch/efi/ip104"
SOURCE_URL="https://efi.igb.illinois.edu/downloads/databases/20250210/"
LOG_FILE="download_$(date +%Y%m%d_%H%M%S).log"
TIMEOUT_MINUTES=30  # Kill if no progress for 30 minutes
CHECK_INTERVAL=60   # Check progress every minute
MAX_RETRIES=3

# Expected files after successful download
EXPECTED_FILES=(
    "$DATA_DIR/blast"          # BLAST database directory
    "$DATA_DIR/diamond"        # DIAMOND database directory  
    "$DATA_DIR/efi_db.sqlite"  # SQLite database file
)

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

check_completion() {
    local all_exist=true
    for file in "${EXPECTED_FILES[@]}"; do
        if [[ ! -e "$file" ]]; then
            all_exist=false
            break
        fi
    done
    echo $all_exist
}

get_directory_size() {
    if [[ -d "$DATA_DIR" ]]; then
        du -s "$DATA_DIR" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

monitor_download() {
    local pid=$1
    local retry_count=$2
    local last_size=$(get_directory_size)
    local no_progress_count=0
    local start_time=$(date +%s)
    
    log_message "Starting monitoring for PID $pid (attempt $((retry_count + 1))/$MAX_RETRIES)"
    log_message "Initial directory size: ${last_size}KB"
    
    while kill -0 $pid 2>/dev/null; do
        sleep $CHECK_INTERVAL
        
        current_size=$(get_directory_size)
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [[ $current_size -gt $last_size ]]; then
            # Progress detected
            no_progress_count=0
            log_message "Progress: ${current_size}KB (+$((current_size - last_size))KB) - Elapsed: ${elapsed}s"
            last_size=$current_size
        else
            # No progress
            no_progress_count=$((no_progress_count + 1))
            log_message "No progress for $((no_progress_count * CHECK_INTERVAL / 60)) minutes (${current_size}KB)"
            
            if [[ $no_progress_count -ge $TIMEOUT_MINUTES ]]; then
                log_message "STUCK DETECTED: No progress for $TIMEOUT_MINUTES minutes. Killing process $pid"
                kill -TERM $pid 2>/dev/null
                sleep 5
                kill -KILL $pid 2>/dev/null
                return 1  # Indicate stuck
            fi
        fi
    done
    
    wait $pid
    return $?  # Return the exit code of the original process
}

attempt_download() {
    local retry_count=$1
    
    log_message "=== Download Attempt $((retry_count + 1))/$MAX_RETRIES ==="
    
    # Check what's already completed
    local completed_files=()
    for file in "${EXPECTED_FILES[@]}"; do
        if [[ -e "$file" ]]; then
            completed_files+=("$file")
        fi
    done
    
    if [[ ${#completed_files[@]} -gt 0 ]]; then
        log_message "Found existing files: ${completed_files[*]}"
    fi
    
    # Start the download
    bash "$DOWNLOAD_SCRIPT" --data-dir "$DATA_DIR" --source-url "$SOURCE_URL" >> "$LOG_FILE" 2>&1 &
    local download_pid=$!
    
    # Monitor the download
    monitor_download $download_pid $retry_count
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_message "Download process completed successfully"
        return 0
    elif [[ $exit_code -eq 1 ]]; then
        log_message "Download stuck - will retry"
        return 1
    else
        log_message "Download failed with exit code $exit_code"
        return $exit_code
    fi
}

# Main execution
log_message "=== Smart Download Started ==="
log_message "Target directory: $DATA_DIR"
log_message "Source URL: $SOURCE_URL"
log_message "Log file: $LOG_FILE"

# Check if already completed
if [[ $(check_completion) == "true" ]]; then
    log_message "All databases already exist. Download appears complete!"
    exit 0
fi

# Attempt downloads with retry
for ((retry=0; retry<MAX_RETRIES; retry++)); do
    attempt_download $retry
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        if [[ $(check_completion) == "true" ]]; then
            log_message "SUCCESS: All databases downloaded successfully!"
            exit 0
        else
            log_message "WARNING: Process completed but some files may be missing"
        fi
    elif [[ $retry -lt $((MAX_RETRIES - 1)) ]]; then
        log_message "Retry $((retry + 1)) failed. Waiting 30 seconds before next attempt..."
        sleep 30
    fi
done

log_message "FAILED: All $MAX_RETRIES attempts failed"
log_message "Check $LOG_FILE for detailed logs"
exit 1
