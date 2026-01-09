#!/bin/bash
#
# Script: analyze_pdfs_pro.sh
# Purpose: Professional-grade PDF analysis and forensic data extraction.
#          Generates comprehensive reports with threat intelligence scoring,
#          memory forensics capabilities, network intelligence integration,
#          and enterprise-level tooling support.
# Usage: ./analyze_pdfs_pro.sh <file.pdf> [<folder/> <another.pdf> ...]
#
# Required Tools: exiftool, pdfinfo, mdls (macOS), strings, binwalk,
#                 ocrmypdf, pdfimages, pdfid.py, pdf-parser.py, qpdf, grep,
#                 pdftotext, pdftohtml, python3 (with pdfplumber), pdffonts,
#                 pdfcpu, pdfgrep, pdfseparate, pdfcrack, pdfsig, shasum,
#                 peepdf.py, peerscan, yara, virustotal-api, pdfreaper
#
#############################################################################
# --- Configuration ---
OUTPUT_BASE_DIR="$HOME/Desktop" # Base directory for output folders
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_OUTPUT_DIR="$OUTPUT_BASE_DIR/forensic_run_${TIMESTAMP}"
REPORT_FILE="$RUN_OUTPUT_DIR/consolidated_forensic_report.txt"
LOG_FILE="$RUN_OUTPUT_DIR/execution_details.log"

# Feature Flags - Set these to true/false based on your needs
RUN_OCR=true                   # Enable slow OCR operation?
RUN_PDFCRACK=false            # Enable slow pdfcrack check?
RUN_QDF_GREP=true             # Enable qpdf unpack and deep grep?
RUN_BINWALK=true              # Enable binwalk scan?
RUN_MDLS=true                 # Attempt to run mdls (macOS only)?
RUN_PEEPDF=true               # Run PeepDF analysis
RUN_PEERSCAN=true             # Run PeerScan analysis
RUN_YARA_SCAN=false            # Run YARA rule scanning
RUN_MEMDUMP=false             # Enable memory dump analysis?
RUN_VIRUSTOTAL=false           # Check files against VirusTotal

# Search keywords (adjust as needed)
KEYWORDS_GREP="client|name|amount|deleted|hidden|xref|annot|sign|sig|malware|exploit|payload|shellcode|javascript"
KEYWORDS_PDFPARSER="client|annot|sig|javascript|js|launch|openaction|uri"
KEYWORDS_STRINGS_SEARCH='₪|€|\$|ID|client|שם|מספר|name|account|password|pass|admin|login|secret|confidential'

# Threat Intelligence Integration
VT_API_KEY="your_vt_api_key_here"  # Replace with your actual VirusTotal API key
YARA_RULES="/opt/yara-rules/pdf_rules.yar"  # Path to YARA rules
MEMORY_DUMP_DIR="/opt/memory_dumps"  # Directory containing memory dumps

# Python environment
PYTHON_CMD="python3"
PDFPLUMBER_SCRIPT_NAME="extract_text_pdp.py"
PDFPLUMBER_SCRIPT_PATH="$(dirname "$(realpath "$0")")/$PDFPLUMBER_SCRIPT_NAME" # Absolute path

# --- Setup ---
# Ensure base output directory exists
mkdir -p "$RUN_OUTPUT_DIR" || { 
    echo "ERROR: Cannot create base output directory '$RUN_OUTPUT_DIR'. Check permissions." >&2; 
    exit 1; 
}

# Initialize Log and Report Files
echo "### PDF Forensic Analysis Run Started: $(date) ###" > "$REPORT_FILE"
echo "### Execution Log Started: $(date) ###" > "$LOG_FILE"
echo "--- Configuration ---" >> "$LOG_FILE"
echo "Output Directory: $RUN_OUTPUT_DIR" >> "$LOG_FILE"
echo "--------------------" >> "$LOG_FILE"

# --- Helper Functions ---
log_msg() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message" | tee -a "$REPORT_FILE" "$LOG_FILE"
}

log_debug() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [DEBUG] $message" >> "$LOG_FILE"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_dependencies() {
    log_debug "Checking dependencies..."
    local missing_deps=0
    
    # Core system utilities
    local deps=(
        exiftool pdfinfo strings binwalk ocrmypdf pdfimages qpdf grep
        pdftotext pdftohtml "$PYTHON_CMD" pdffonts pdfcpu pdfgrep
        pdfseparate pdfcrack pdfsig shasum find tee date basename dirname mkdir rm head awk
        pdfid.py pdf-parser.py
    )
    
    # Additional tools for advanced analysis
   #ß if [[ "$RUN_PEEPDF" == true ]]; then deps+=("peepdf/main.py"); fi
    #if [[ "$RUN_PEERSCAN" == true ]]; then deps+=("peerscan"); fi
    if [[ "$RUN_YARA_SCAN" == true ]]; then deps+=("yara64"); fi
    if [[ "$RUN_VIRUSTOTAL" == true ]]; then deps+=("curl"); fi
    
    # macOS-specific tools
    if [[ "$(uname)" == "Darwin" ]] && [[ "$RUN_MDLS" == true ]]; then
        deps+=("mdls")
    fi

    for cmd in "${deps[@]}"; do
        if ! command_exists "$cmd"; then
            log_msg "ERROR" "Required command '$cmd' not found in PATH."
            missing_deps=$((missing_deps + 1))
        else
             log_debug "Dependency check passed for: $cmd"
        fi
    done
    
    # Check Python modules
    if ! "$PYTHON_CMD" -c "import pdfplumber" >> "$LOG_FILE" 2>&1; then
         log_msg "WARN" "Python module 'pdfplumber' not found or $PYTHON_CMD failed. Install via 'pip3 install pdfplumber'."
    else
         log_debug "Python module 'pdfplumber' found."
    fi
    
    if [[ $missing_deps -gt 0 ]]; then
        log_msg "ERROR" "$missing_deps critical dependencies missing. Please install them and ensure they are in your PATH."
        exit 1
    fi
    
    log_msg "INFO" "Dependency check passed."
}

calculate_threat_score() {
    local score=0
    
    # Check for suspicious elements
    if grep -q "javascript" "$REPORT_FILE"; then ((score+=30)); fi
    if grep -q "launch" "$REPORT_FILE"; then ((score+=25)); fi
    if grep -q "EmbeddedFile" "$REPORT_FILE"; then ((score+=20)); fi
    if grep -q "ObjStm" "$REPORT_FILE"; then ((score+=15)); fi
    if grep -q "XFA" "$REPORT_FILE"; then ((score+=25)); fi
    #if grep -q "Encrypt" "$REPORT_FILE"); then ((score+=35)); fi
    
    # Cap score at 100
    score=$((score > 100 ? 100 : score))
    
    echo -e "\n=== Threat Score ===" >> "$REPORT_FILE"
    echo "Calculated Threat Score: $score/100" >> "$REPORT_FILE"
    
    if [[ $score -ge 75 ]]; then
        echo "[ALERT] High-risk indicators detected!" >> "$REPORT_FILE"
    elif [[ $score -ge 50 ]]; then
        echo "[WARNING] Medium-risk indicators detected" >> "$REPORT_FILE"
    else
        echo "[INFO] Low-risk profile" >> "$REPORT_FILE"
    fi
}

# --- Processing Functions ---
generate_html_report() {
    local pdf_file="$1"
    local out_dir="$2"
    local base_pdf_name=$(basename -s .pdf -s .PDF "$pdf_file")
    local html_file="$out_dir/${base_pdf_name}_metadata_report.html"
    log_debug "Generating HTML report: $html_file"
    
    cat > "$html_file" <<-EOF
<html><head><meta charset='UTF-8'>
<style>
body { font-family: sans-serif; background: #fdfdfd; padding: 15px; margin: 0; font-size: 14px; }
h1 { border-bottom: 2px solid #666; padding-bottom: 5px; color: #333; font-size: 1.5em; }
h2 { background: #eee; border-left: 5px solid #aaa; padding: 8px 12px; margin-top: 25px; font-size: 1.2em; color: #444;}
pre { background: #f4f4f4; border: 1px solid #ddd; padding: 10px; white-space: pre-wrap; word-wrap: break-word; font-family: monospace; font-size: 12px; line-height: 1.4; }
.error { color: #D8000C; background-color: #FFD2D2; border: 1px solid #D8000C; padding: 5px; font-weight: bold; display: block; margin-top: 5px;}
</style><title>PDF Metadata Report: $base_pdf_name</title></head><body>
<h1>PDF Metadata Report: $base_pdf_name</h1>
EOF

    # Exiftool Metadata
    echo "<h2>Exiftool Metadata</h2><pre>" >> "$html_file"
    if output=$(exiftool "$pdf_file" 2>> "$LOG_FILE"); then
        output=$(echo "$output" | sed 's/&/\&/g; s/</\</g; s/>/\>/g')
        echo "$output" >> "$html_file"
    else
        local exit_code=$?
        echo "<span class='error'>[ERROR] Failed to run exiftool (Exit code: $exit_code)</span>" >> "$html_file"
        log_msg "WARN" "Exiftool failed for $base_pdf_name (Code: $exit_code)"
    fi
    echo "</pre>" >> "$html_file"
    
    # pdfinfo Metadata
    echo "<h2>PDF Info</h2><pre>" >> "$html_file"
    if output=$(pdfinfo "$pdf_file" 2>> "$LOG_FILE"); then
        output=$(echo "$output" | sed 's/&/\&/g; s/</\</g; s/>/\>/g')
        echo "$output" >> "$html_file"
    else
        local exit_code=$?
        echo "<span class='error'>[ERROR] Failed to run pdfinfo (Exit code: $exit_code)</span>" >> "$html_file"
        log_msg "WARN" "pdfinfo failed for $base_pdf_name (Code: $exit_code)"
    fi
    echo "</pre>" >> "$html_file"
    
    # pdfsig info
    echo "<h2>Digital Signature (pdfsig)</h2><pre>" >> "$html_file"
    if output=$(pdfsig "$pdf_file" 2>> "$LOG_FILE"); then
         output=$(echo "$output" | sed 's/&/\&/g; s/</\</g; s/>/\>/g')
         echo "$output" >> "$html_file"
    else
         local exit_code=$?
         echo "<span class='error'>[INFO] pdfsig check failed or no signature found (Exit code: $exit_code)</span>" >> "$html_file"
         if [[ $exit_code -gt 2 ]]; then log_msg "WARN" "pdfsig failed for $base_pdf_name (Code: $exit_code)"; fi
    fi
     echo "</pre>" >> "$html_file"
    echo "</body></html>" >> "$html_file"
    
    log_msg "INFO" "HTML metadata report generated for '$base_pdf_name': $html_file"
}

run_forensic_scan() {
    local pdf_file="$1"
    local out_dir="$2"
    local base_pdf_name=$(basename -s .pdf -s .PDF "$pdf_file")
    log_debug "Starting forensic scan for $pdf_file"
    
    echo -e "
=================================================" >> "$REPORT_FILE"
    echo "### Forensic Scan Results for: $pdf_file ###" >> "$REPORT_FILE"
    echo "Timestamp: $(date)" >> "$REPORT_FILE"
    echo "Output Directory: $out_dir" >> "$REPORT_FILE"
    echo "=================================================" >> "$REPORT_FILE"
    
    # --- Hashes ---
    echo -e "
=== File Hashes ===" >> "$REPORT_FILE"
    shasum -a 256 "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "Failed to calculate SHA256 for $base_pdf_name"
    shasum -a 1 "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "Failed to calculate SHA1 for $base_pdf_name"
    
    # --- Embedded Artifact Extraction ---
    echo -e "
=== Extracting Embedded Artifacts ===" >> "$REPORT_FILE"
    local artifact_dir="$out_dir/embedded_artifacts"
    mkdir -p "$artifact_dir"
    
    # Deep binwalk extraction
    if [[ "$RUN_BINWALK" == true ]]; then
        log_debug "Running Binwalk deep extraction..."
        binwalk -e --directory="$artifact_dir" "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "Binwalk extraction failed for $base_pdf_name"
        
        if [[ $(ls -A "$artifact_dir") ]]; then
            echo "[INFO] Embedded artifacts extracted to: $artifact_dir" >> "$REPORT_FILE"
        else
            echo "[INFO] No embedded artifacts found by Binwalk." >> "$REPORT_FILE"
        fi
    else
        echo "[INFO] Binwalk extraction skipped per configuration." >> "$REPORT_FILE"
    fi
    
    # Enhanced object extraction
    echo -e "
=== PDF Object Extraction ===" >> "$REPORT_FILE"
    local objects_dir="$out_dir/pdf_objects"
    mkdir -p "$objects_dir"
    
    pdf-parser.py -s objects "$pdf_file" > "$objects_dir/objects.txt" 2>> "$LOG_FILE"
    pdf-parser.py -s xref "$pdf_file" > "$objects_dir/xref_table.txt" 2>> "$LOG_FILE"
    pdf-parser.py -s trailer "$pdf_file" > "$objects_dir/trailer.txt" 2>> "$LOG_FILE"
    
    # --- Memory Forensics Capabilities ---
    if [[ "$RUN_MEMDUMP" == true && -d "$MEMORY_DUMP_DIR" ]]; then
        echo -e "
=== Memory Dump Analysis ===" >> "$REPORT_FILE"
        local memscan_dir="$out_dir/memory_analysis"
        mkdir -p "$memscan_dir"
        
        for mem_file in "$MEMORY_DUMP_DIR"/*; do
            if [[ -f "$mem_file" ]]; then
                mem_base=$(basename "$mem_file")
                echo "[INFO] Scanning memory dump: $mem_base" >> "$REPORT_FILE"
                
                # Scan for PDF content in memory dumps
                strings "$mem_file" | grep -A 5 -B 5 -i "$(shasum -a 256 "$pdf_file" | awk '{print $1}')" > "$memscan_dir/$mem_base.matches" 2>> "$LOG_FILE"
                
                if [[ -s "$memscan_dir/$mem_base.matches" ]]; then
                    echo "[INFO] Found potential matches in $mem_base" >> "$REPORT_FILE"
                fi
            fi
        done
    fi
    
    # --- Network Intelligence Integration ---
    if [[ "$RUN_VIRUSTOTAL" == true && -n "$VT_API_KEY" ]]; then
        echo -e "
=== VirusTotal File Check ===" >> "$REPORT_FILE"
        local vt_hash=$(shasum -a 256 "$pdf_file" | awk '{print $1}')
        
        # Check hash against VirusTotal
        curl -s --get --data "resource=$vt_hash&apikey=$VT_API_KEY" "https://www.virustotal.com/vtapi/v2/file/report" >> "$REPORT_FILE" 2>> "$LOG_FILE"
    fi
    
    # --- Advanced Forensic Tools Integration ---
    if [[ "$RUN_PEEPDF" == true ]]; then
        echo -e "
=== PeepDF Analysis ===" >> "$REPORT_FILE"
        peepdf.py -i "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "PeepDF analysis failed for $base_pdf_name"
    fi

    if [[ "$RUN_PEERSCAN" == true ]]; then
        echo -e "
=== PeerScan Deep Analysis ===" >> "$REPORT_FILE"
        python3 peerscan/peerscan.py --all "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "PeerScan failed for $base_pdf_name"
    fi

    if [[ "$RUN_YARA_SCAN" == true && -f "$YARA_RULES" ]]; then
        echo -e "
=== YARA Rule Scan ===" >> "$REPORT_FILE"
        yara64 -r "$YARA_RULES" "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "YARA scan failed for $base_pdf_name"
    fi
    
    # --- Threat Intelligence Scoring ---
    calculate_threat_score
    
    echo -e "
--- End of Scan for: $pdf_file ---" >> "$REPORT_FILE"
}

process_pdf() {
    local pdf_file="$1"
    log_debug "Entered process_pdf with file: '$pdf_file'"
    local base_name_with_path=$(basename -s .pdf -s .PDF "$pdf_file")
    local base_name=$(basename "$base_name_with_path")
    local out_dir="$RUN_OUTPUT_DIR/$base_name"
    log_debug "Calculated base_name: '$base_name'"
    log_debug "Calculated out_dir: '$out_dir'"
    log_debug "Attempting to create output directory '$out_dir'"
    
    # Sanitize path separators to prevent directory traversal attacks
    local sanitized_base="${base_name//[\/]/_}"
    local out_dir="$RUN_OUTPUT_DIR/$sanitized_base"
    
    if ! mkdir -p "$out_dir"; then
        log_msg "ERROR" "Failed to create output directory '$out_dir'. Check permissions and path validity."
        return 1
    fi
    
    log_msg "INFO" "Successfully created output directory: '$out_dir'"
    log_debug "Output directory should now exist: '$out_dir'"
    log_msg "INFO" "Calculating hash for: $base_name"
    log_debug "Running shasum command for $pdf_file"
    
    if ! shasum -a 256 "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE"; then
         log_msg "WARN" "Failed to calculate SHA256 hash for '$base_name'"
         log_debug "shasum failed for $pdf_file"
    fi
    
    log_msg "INFO" "Generating HTML report for: $base_name"
    log_debug "Calling generate_html_report for '$pdf_file' into '$out_dir'"
    generate_html_report "$pdf_file" "$out_dir"
    
    log_msg "INFO" "Running forensic scan for: $base_name"
    log_debug "Calling run_forensic_scan for '$pdf_file' into '$out_dir'"
    run_forensic_scan "$pdf_file" "$out_dir"
    
    log_msg "INFO" "Finished processing: $base_name"
    log_debug "Exiting process_pdf for file: '$pdf_file'"
    echo -e "
#############################################################################
" >> "$REPORT_FILE"
}

# --- Main Execution Logic ---
main() {
    if [[ "$(id -u)" -eq 0 ]]; then
       log_msg "WARN" "Running this script as root (sudo) is generally not recommended."
    fi
    
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <file.pdf | folder> [<file.pdf | folder> ...]" >&2
        echo "Example: $0 document.pdf /path/to/scans/" >&2
        exit 1
    fi
    
    check_dependencies
    log_msg "INFO" "Processing $# input path(s)... Output base: $RUN_OUTPUT_DIR"
    
    local processed_files_count=0
    local error_count=0
    
    for input_path in "$@"; do
        log_debug "Processing input argument: $input_path"
        
        # Sanitize input paths to prevent path traversal attacks
        local safe_input_path="$(cd "$(dirname "$input_path")"; pwd)/$(basename "$input_path")"
        
        if [[ -d "$safe_input_path" ]]; then
            log_msg "INFO" "Input is a directory, searching for PDF files in: $safe_input_path"
            
            while IFS= read -r -d $'\0' pdf_file; do
                if [[ -n "$pdf_file" ]]; then
                     log_debug "Found PDF in directory: $pdf_file"
                     process_pdf "$pdf_file"
                     if [[ $? -ne 0 ]]; then error_count=$((error_count + 1)); fi
                     processed_files_count=$((processed_files_count + 1))
                fi
            done < <(find "$safe_input_path" -type f \( -iname "*.pdf" \) -print0 2>> "$LOG_FILE")
            
        elif [[ -f "$safe_input_path" && "${safe_input_path##*.}" =~ ^[pP][dD][fF]$ ]]; then
            log_msg "INFO" "Processing PDF file: $safe_input_path"
            process_pdf "$safe_input_path"
            if [[ $? -ne 0 ]]; then error_count=$((error_count + 1)); fi
            processed_files_count=$((processed_files_count + 1))
            
        elif [[ -f "$safe_input_path" ]]; then
            log_msg "WARN" "Input '$safe_input_path' is a file but not a PDF (*.pdf). Skipping."
            
        elif [[ -e "$safe_input_path" ]]; then
             log_msg "WARN" "Input '$safe_input_path' exists but is not a regular file or directory. Skipping."
             
        else
            log_msg "ERROR" "Input '$safe_input_path' not found. Skipping."
            error_count=$((error_count + 1))
        fi
    done
    
    log_msg "INFO" "Script finished. Processed $processed_files_count PDF file(s) with $error_count error(s) during processing."
    log_msg "INFO" "Consolidated report: $REPORT_FILE"
    log_msg "INFO" "Detailed execution log: $LOG_FILE"
    log_msg "INFO" "Individual file outputs are in subdirectories within: $RUN_OUTPUT_DIR"
    
    if [[ "$(uname)" == "Darwin" ]]; then
        if [ "$(ls -A "$RUN_OUTPUT_DIR" | grep -v consolidated_forensic_report.txt | grep -v execution_details.log)" ]; then
            log_msg "INFO" "Opening output directory: $RUN_OUTPUT_DIR"
            open "$RUN_OUTPUT_DIR"
        else
            log_msg "INFO" "Output directory is empty or only contains log/report files. Not opening."
        fi
    fi
}

# --- Run Main Function ---
main "$@"
exit 0