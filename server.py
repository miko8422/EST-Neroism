#!/usr/bin/env python3
"""
FASTA Processing API Server
Runs on local Linux machine to process FASTA files through command pipeline
"""

import os
import subprocess
import tempfile
import shutil
import glob
import zipfile
from flask import Flask, request, send_file, jsonify
from werkzeug.utils import secure_filename
import logging

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# Base directory for processing
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
FASTA_CACHE_DIR = os.path.join(BASE_DIR, "data", "fasta_cache")
RESULTS_DIR = os.path.join(BASE_DIR, "results", "final_ssn")

# Ensure directories exist
os.makedirs(FASTA_CACHE_DIR, exist_ok=True)
os.makedirs(RESULTS_DIR, exist_ok=True)

def cleanup_work_directory():
    """Clean up the work directory after processing"""
    try:
        if os.path.exists(RESULTS_DIR):
            logger.info(f"Cleaning up work directory: {RESULTS_DIR}")
            shutil.rmtree(RESULTS_DIR)
            os.makedirs(RESULTS_DIR, exist_ok=True)
            logger.info("Work directory cleaned successfully")
    except Exception as e:
        logger.warning(f"Failed to clean work directory: {e}")

def create_result_zip(output_dir):
    """
    Create a zip file containing the three required output files
    Returns the path to the zip file or None if files not found
    """
    required_files = [
        "ssn.xgmml",
        "filtered_sequence_metadata.tab", 
        "filtered_sequences.fasta"
    ]
    
    # Search for files in the output directory
    found_files = {}
    
    for root, dirs, files in os.walk(output_dir):
        for file in files:
            for required_file in required_files:
                if file.endswith(required_file.split('.')[-1]) and required_file.split('.')[0] in file:
                    found_files[required_file] = os.path.join(root, file)
                    logger.info(f"Found {required_file}: {found_files[required_file]}")
    
    # Check if we found all required files
    missing_files = [f for f in required_files if f not in found_files]
    if missing_files:
        logger.warning(f"Missing required files: {missing_files}")
        # Try alternative search for missing files
        for missing_file in missing_files:
            pattern = f"**/*{missing_file.split('.')[-1]}"
            matches = glob.glob(os.path.join(output_dir, pattern), recursive=True)
            logger.info(f"Alternative search for {missing_file}: {matches}")
            
            # Use heuristics to find the right file
            for match in matches:
                basename = os.path.basename(match).lower()
                if missing_file == "ssn.xgmml" and "ssn" in basename and match.endswith(".xgmml"):
                    found_files[missing_file] = match
                    break
                elif missing_file == "filtered_sequence_metadata.tab" and ("metadata" in basename or "filtered" in basename) and match.endswith(".tab"):
                    found_files[missing_file] = match
                    break
                elif missing_file == "filtered_sequences.fasta" and ("filtered" in basename or "sequence" in basename) and match.endswith(".fasta"):
                    found_files[missing_file] = match
                    break
    
    # Final check
    still_missing = [f for f in required_files if f not in found_files]
    if still_missing:
        logger.error(f"Could not find required files: {still_missing}")
        return None, still_missing
    
    # Create zip file
    zip_path = os.path.join(output_dir, "results.zip")
    try:
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for required_file, file_path in found_files.items():
                if os.path.exists(file_path):
                    zipf.write(file_path, required_file)
                    logger.info(f"Added {required_file} to zip")
                else:
                    logger.error(f"File not found when creating zip: {file_path}")
                    return None, [required_file]
        
        logger.info(f"Created result zip: {zip_path}")
        return zip_path, []
        
    except Exception as e:
        logger.error(f"Failed to create zip file: {e}")
        return None, ["zip_creation_error"]

def run_command(command, cwd=None):
    """Execute a shell command and return output"""
    logger.info(f"Running command: {command}")
    logger.info(f"Working directory: {cwd or BASE_DIR}")
    
    # Set up environment with EFI_DATA_DIR
    env = os.environ.copy()
    env['EFI_DATA_DIR'] = os.path.join(BASE_DIR, 'data', 'efi')
    logger.info(f"EFI_DATA_DIR set to: {env['EFI_DATA_DIR']}")
    
    result = subprocess.run(
        command,
        shell=True,
        capture_output=True,
        text=True,
        cwd=cwd or BASE_DIR,
        env=env
    )
    
    logger.info(f"Return code: {result.returncode}")
    logger.info(f"STDOUT:\n{result.stdout}")
    logger.info(f"STDERR:\n{result.stderr}")
    
    if result.returncode != 0:
        logger.error(f"Command failed with return code {result.returncode}")
        # Don't raise exception - let the process continue to see what happens
    
    return result

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    return jsonify({"status": "healthy"}), 200

@app.route('/process', methods=['POST'])
def process_fasta():
    """Main endpoint to process FASTA file"""
    # Clean up any previous work
    cleanup_work_directory()
    
    try:
        # Validate input
        if 'file' not in request.files:
            return jsonify({"error": "No file provided"}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({"error": "No file selected"}), 400
        
        # Get filter_min_val parameter
        filter_min_val = request.form.get('filter_min_val', '23')
        logger.info(f"Filter min val: {filter_min_val}")
        
        # Save uploaded file
        filename = secure_filename(file.filename)
        if not filename.endswith('.fasta'):
            filename = 'test.fasta'
        
        fasta_path = os.path.join(FASTA_CACHE_DIR, filename)
        file.save(fasta_path)
        logger.info(f"Saved FASTA file to: {fasta_path}")
        logger.info(f"File size: {os.path.getsize(fasta_path)} bytes")
        
        # Define paths
        blastdb_path = os.path.join(FASTA_CACHE_DIR, "test_blastdb")
        
        # Step 1: Create BLAST database
        cmd1 = f"makeblastdb -in {fasta_path} -dbtype prot -out {blastdb_path}"
        result1 = run_command(cmd1)
        
        # Check if BLAST DB was created
        logger.info(f"Checking for BLAST DB files at: {blastdb_path}*")
        blast_files = [f for f in os.listdir(FASTA_CACHE_DIR) if f.startswith("test_blastdb")]
        logger.info(f"Found BLAST DB files: {blast_files}")
        
        # Step 2: Create EST nextflow parameters
        cmd2 = (
            f"python bin/create_est_nextflow_params.py fasta "
            f"--fasta-file {fasta_path} "
            f"--fasta-db {blastdb_path} "
            f"--output-dir {RESULTS_DIR} "
            f"--efi-config ./data/efi/efi.config "
            f"--efi-db ./data/efi/efi_db.sqlite "
            f"--nextflow-config conf/est/docker.config"
        )
        result2 = run_command(cmd2)
        
        # Check what was created in the output directory
        logger.info(f"Checking output directory: {RESULTS_DIR}")
        if os.path.exists(RESULTS_DIR):
            for root, dirs, files in os.walk(RESULTS_DIR):
                for file in files:
                    logger.info(f"Found file: {os.path.join(root, file)}")
        
        # Step 3: Run EST nextflow
        est_nextflow_script = os.path.join(RESULTS_DIR, "run_nextflow.sh")
        logger.info(f"Looking for EST nextflow script at: {est_nextflow_script}")
        if os.path.exists(est_nextflow_script):
            logger.info("Found EST nextflow script, running it...")
            # Read the script content for debugging
            with open(est_nextflow_script, 'r') as f:
                script_content = f.read()
                logger.info(f"Script content:\n{script_content[:500]}...")  # First 500 chars
            result3 = run_command(f"bash {est_nextflow_script}")
        else:
            logger.warning(f"EST nextflow script not found at {est_nextflow_script}")
            logger.info("Continuing anyway...")
        
        # Step 4: Create SSN nextflow parameters
        cmd4 = (
            f"python bin/create_generatessn_nextflow_params.py auto "
            f"--filter-min-val {filter_min_val} "
            f"--ssn-name ssn.xgmml "
            f'--ssn-title "Test SSN" '
            f"--est-output-dir {RESULTS_DIR} "
            f"--efi-config ./data/efi/efi.config "
            f"--efi-db ./data/efi/efi_db.sqlite "
            f"--nextflow-config conf/est/docker.config"
        )
        result4 = run_command(cmd4)
        
        # Step 5: Run SSN nextflow
        ssn_nextflow_script = os.path.join(RESULTS_DIR, "ssn", "run_nextflow.sh")
        logger.info(f"Looking for SSN nextflow script at: {ssn_nextflow_script}")
        if os.path.exists(ssn_nextflow_script):
            logger.info("Found SSN nextflow script, running it...")
            result5 = run_command(f"bash {ssn_nextflow_script}")
        else:
            logger.warning(f"SSN nextflow script not found at {ssn_nextflow_script}")
            logger.info("Continuing to look for output files...")
        
        # List all files in results directory for debugging
        logger.info("Final directory structure:")
        for root, dirs, files in os.walk(RESULTS_DIR):
            level = root.replace(RESULTS_DIR, '').count(os.sep)
            indent = ' ' * 2 * level
            logger.info(f"{indent}{os.path.basename(root)}/")
            subindent = ' ' * 2 * (level + 1)
            for file in files:
                logger.info(f"{subindent}{file}")
        
        # Create zip file with all required outputs
        zip_path, missing_files = create_result_zip(RESULTS_DIR)
        
        if zip_path and os.path.exists(zip_path):
            logger.info(f"Success! Sending zip file: {zip_path}")
            return send_file(
                zip_path,
                mimetype='application/zip',
                as_attachment=True,
                download_name='results.zip'
            )
        else:
            error_msg = f"Failed to create results package. Missing files: {missing_files}"
            logger.error(error_msg)
            return jsonify({"error": error_msg, "missing_files": missing_files}), 500
            
    except Exception as e:
        logger.error(f"Unexpected error during processing: {e}")
        return jsonify({"error": f"Processing failed: {str(e)}"}), 500
    
    finally:
        # Clean up work directory after processing (regardless of success/failure)
        cleanup_work_directory()

if __name__ == '__main__':
    # Run the server
    port = int(os.environ.get('PORT', 56100))
    logger.info(f"Starting server on port {port}")
    app.run(host='0.0.0.0', port=port, debug=True)
