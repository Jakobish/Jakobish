#!/bin/bash
#
# Script: analyze_pdfs_v2.sh
# Purpose: Refactored script for PDF analysis and forensic data extraction.
#          Generates an HTML metadata report per PDF and a consolidated
#          text-based forensic report for all processed files in a run.
# Usage: ./analyze_pdfs_v2.sh <file.pdf> [<folder/> <another.pdf> ...]
#
# Required Tools: exiftool, pdfinfo, mdls (macOS), strings, binwalk,
#                 ocrmypdf, pdfimages, pdfid.py, pdf-parser.py, qpdf, grep,
#                 pdftotext, pdftohtml, python3 (with pdfplumber), pdffonts,
#                 pdfcpu, pdfgrep, pdfseparate, pdfcrack, pdfsig, shasum.
#                 Install pdfplumber via: pip3 install pdfplumber
#
#############################################################################
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# --- Configuration ---
OUTPUT_BASE_DIR="./" # Base directory for output folders
RUN_OCR=true                   # Enable slow OCR operation?
RUN_PDFCRACK=false              # Enable slow pdfcrack check?
RUN_QDF_GREP=true               # Enable qpdf unpack and deep grep?
RUN_BINWALK=true                # Enable binwalk scan?
RUN_MDLS=true                   # Attempt to run mdls (macOS only)?

# Search keywords (adjust as needed)
KEYWORDS_GREP="client|name|amount|deleted|hidden|xref|annot|sign|sig"
KEYWORDS_PDFPARSER="client|annot|sig|javascript|js" # Pipe-separated
KEYWORDS_STRINGS_SEARCH='₪|€|\$|ID|client|שם|מספר|name|account' # Grep ERE

PYTHON_CMD="python3"
# Assumes the python script is in the same directory or in PATH
PDFPLUMBER_SCRIPT_NAME="extract_text_pdp.py"
PDFPLUMBER_SCRIPT_PATH="$(dirname "$0")/$PDFPLUMBER_SCRIPT_NAME" # Path relative to this script

# --- Setup ---
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RUN_OUTPUT_DIR="$OUTPUT_BASE_DIR/forensic_run_${TIMESTAMP}"
REPORT_FILE="$RUN_OUTPUT_DIR/consolidated_forensic_report.txt"
LOG_FILE="$RUN_OUTPUT_DIR/execution_details.log"

# Extend PATH if needed (especially for GUI execution)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Ensure base output directory exists
mkdir -p "$RUN_OUTPUT_DIR" || { echo "ERROR: Cannot create base output directory '$RUN_OUTPUT_DIR'. Check permissions." >&2; exit 1; }

# Initialize Log and Report Files
# Use printf for better formatting control if needed later
echo "### PDF Forensic Analysis Run Started: $(date) ###" > "$REPORT_FILE"
echo "### Execution Log Started: $(date) ###" > "$LOG_FILE"
echo "--- Configuration ---" >> "$LOG_FILE"
echo "Output Directory: $RUN_OUTPUT_DIR" >> "$LOG_FILE"
echo "RUN_OCR=$RUN_OCR" >> "$LOG_FILE"
echo "RUN_PDFCRACK=$RUN_PDFCRACK" >> "$LOG_FILE"
echo "RUN_QDF_GREP=$RUN_QDF_GREP" >> "$LOG_FILE"
echo "RUN_BINWALK=$RUN_BINWALK" >> "$LOG_FILE"
echo "RUN_MDLS=$RUN_MDLS" >> "$LOG_FILE"
echo "--------------------" >> "$LOG_FILE"

# --- Helper Functions ---

# Usage: log_msg "LEVEL" "Message"
# LEVEL: INFO, WARN, ERROR
log_msg() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    # Log to report file (and echo to stdout via tee)
    echo "[$timestamp] [$level] $message" | tee -a "$REPORT_FILE"
    # Also log to the detailed execution log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Usage: log_debug "Message" (only goes to log file)
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
    local deps=(
        exiftool pdfinfo strings binwalk ocrmypdf pdfimages qpdf grep
        pdftotext pdftohtml "$PYTHON_CMD" pdffonts pdfcpu pdfgrep
        pdfseparate pdfcrack pdfsig shasum find tee date basename dirname mkdir rm head awk
        pdfid.py pdf-parser.py # Assuming installed via oletools or PATH setup
    )
    # Add macOS specific check
    if [[ "$(uname)" == "Darwin" ]] && [[ "$RUN_MDLS" == true ]]; then
        deps+=("mdls")
    fi

    for cmd in "${deps[@]}"; do
        if ! command_exists "$cmd"; then
            # Log error to both console/report and log file
            log_msg "ERROR" "Required command '$cmd' not found in PATH."
            missing_deps=$((missing_deps + 1))
        else
             log_debug "Dependency check passed for: $cmd"
        fi
    done

    if [[ $missing_deps -gt 0 ]]; then
        log_msg "ERROR" "$missing_deps critical dependencies missing. Please install them and ensure they are in your PATH."
        exit 1
    fi
    log_msg "INFO" "Dependency check passed." # Log success to main report too
}

# --- Processing Functions ---

generate_html_report() {
    local pdf_file="$1"
    local out_dir="$2"
    local base_pdf_name=$(basename -s .pdf -s .PDF "$pdf_file")
    local html_file="$out_dir/${base_pdf_name}_metadata_report.html"

    log_debug "Generating HTML report: $html_file"

    # Start HTML
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
        # Basic HTML escaping for safety, though exiftool output is usually safe
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

    # Add pdfsig info to HTML report too?
    echo "<h2>Digital Signature (pdfsig)</h2><pre>" >> "$html_file"
    if output=$(pdfsig "$pdf_file" 2>> "$LOG_FILE"); then
         output=$(echo "$output" | sed 's/&/\&/g; s/</\</g; s/>/\>/g')
         echo "$output" >> "$html_file"
    else
         local exit_code=$?
         echo "<span class='error'>[INFO] pdfsig check failed or no signature found (Exit code: $exit_code)</span>" >> "$html_file"
         # Don't log warning if it just means no signature found (often exit code 1 or 2)
         if [[ $exit_code -gt 2 ]]; then log_msg "WARN" "pdfsig failed for $base_pdf_name (Code: $exit_code)"; fi
    fi
     echo "</pre>" >> "$html_file"

    # End HTML
    echo "</body></html>" >> "$html_file"

    log_msg "INFO" "HTML metadata report generated for '$base_pdf_name': $html_file"
}

run_forensic_scan() {
    local pdf_file="$1"
    local out_dir="$2"
    local base_pdf_name=$(basename -s .pdf -s .PDF "$pdf_file")

    log_debug "Starting forensic scan for $pdf_file"
    echo -e "\n\n=================================================" >> "$REPORT_FILE"
    echo "### Forensic Scan Results for: $pdf_file ###" >> "$REPORT_FILE"
    echo "Timestamp: $(date)" >> "$REPORT_FILE"
    echo "Output Directory: $out_dir" >> "$REPORT_FILE"
    echo "=================================================" >> "$REPORT_FILE"

    # --- Hashes ---
    echo -e "\n=== File Hashes ===" >> "$REPORT_FILE"
    shasum -a 256 "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "Failed to calculate SHA256 for $base_pdf_name"
    shasum -a 1 "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "Failed to calculate SHA1 for $base_pdf_name"

    # --- Metadata Tools (Adding mdls conditionally) ---
    if [[ "$(uname)" == "Darwin" ]] && [[ "$RUN_MDLS" == true ]]; then
        echo -e "\n=== Spotlight Metadata (mdls - macOS only) ===" >> "$REPORT_FILE"
        mdls "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "mdls command failed for $base_pdf_name"
    fi

    # --- Text Extraction ---
    echo -e "\n=== Raw Strings (grep '${KEYWORDS_STRINGS_SEARCH}') ===" >> "$REPORT_FILE"
    # Using LC_ALL=C to avoid issues with invalid byte sequences
    LC_ALL=C strings "$pdf_file" | grep -Eahi "$KEYWORDS_STRINGS_SEARCH" | head -n 100 >> "$REPORT_FILE" 2>> "$LOG_FILE"
    echo "[INFO] Searched strings for keywords (max 100 lines)." >> "$REPORT_FILE"

    echo -e "\n=== PDFToText Extraction ===" >> "$REPORT_FILE"
    local txt_output_file="$out_dir/${base_pdf_name}_pdftotext.txt"
    pdftotext "$pdf_file" "$txt_output_file" 2>> "$LOG_FILE"
    if [[ $? -eq 0 ]]; then
        echo "[INFO] Full text extracted by pdftotext to: $txt_output_file" >> "$REPORT_FILE"
    else
        log_msg "WARN" "pdftotext failed for $base_pdf_name (Exit code: $?)"
        echo "[WARN] pdftotext extraction failed." >> "$REPORT_FILE"
    fi

    if [[ "$RUN_OCR" == true ]]; then
        echo -e "\n=== OCR Sidecar Text Preview (Head) ===" >> "$REPORT_FILE"
        log_debug "Running OCRmypdf for sidecar preview..."
        # This can be slow! Redirect stderr to log file
        ocrmypdf --sidecar - "$pdf_file" - 2>> "$LOG_FILE" | head -n 50 >> "$REPORT_FILE"
        local ocr_exit_code=$?
        if [[ $ocr_exit_code -ne 0 ]]; then
             log_msg "WARN" "ocrmypdf sidecar preview failed for $base_pdf_name (Code: $ocr_exit_code)"
             echo "[WARN] OCR sidecar generation failed." >> "$REPORT_FILE"
        else
             echo "[INFO] OCR sidecar generated (preview shown)." >> "$REPORT_FILE"
        fi
    else
        echo -e "\n=== OCR Sidecar Text Preview (Skipped) ===" >> "$REPORT_FILE"
    fi

    echo -e "\n=== PDFPlumber Text Extraction (Python) ===" >> "$REPORT_FILE"
    if [[ -f "$PDFPLUMBER_SCRIPT_PATH" ]]; then
        "$PYTHON_CMD" "$PDFPLUMBER_SCRIPT_PATH" "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE"
         if [[ $? -ne 0 ]]; then log_msg "WARN" "pdfplumber script '$PDFPLUMBER_SCRIPT_NAME' failed for $base_pdf_name"; fi
    else
        log_msg "WARN" "PDFPlumber helper script '$PDFPLUMBER_SCRIPT_PATH' not found. Skipping extraction."
        echo "[WARN] PDFPlumber script not found at expected location." >> "$REPORT_FILE"
    fi

    # --- Structure & Content Analysis Tools ---
    echo -e "\n=== PDFiD Scan ===" >> "$REPORT_FILE"
    pdfid.py "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "pdfid.py failed for $base_pdf_name"

    echo -e "\n=== PDF Parser Search (Keywords: ${KEYWORDS_PDFPARSER}) ===" >> "$REPORT_FILE"
    pdf-parser.py -k "$KEYWORDS_PDFPARSER" "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "pdf-parser.py search failed for $base_pdf_name"

    echo -e "\n=== PDFFonts ===" >> "$REPORT_FILE"
    pdffonts "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "pdffonts failed for $base_pdf_name"

    echo -e "\n=== PDF Images List & Extraction ===" >> "$REPORT_FILE"
    local img_dir="$out_dir/extracted_images"
    pdfimages -list "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE"
    log_debug "Attempting to extract images..."
    mkdir -p "$img_dir"
    pdfimages -all "$pdf_file" "$img_dir/$base_pdf_name" 2>> "$LOG_FILE" # Extracts as png/jpg/etc.
    # Check if any files were actually created
    if compgen -G "$img_dir/${base_pdf_name}*" > /dev/null; then
        echo "[INFO] Images extracted to: $img_dir" >> "$REPORT_FILE"
    else
        echo "[INFO] No images found or extracted by pdfimages." >> "$REPORT_FILE"
        rmdir "$img_dir" 2>/dev/null # Clean up empty dir
    fi

    if [[ "$RUN_BINWALK" == true ]]; then
        echo -e "\n=== Binwalk Scan (Potential Embedded Files) ===" >> "$REPORT_FILE"
        log_debug "Running Binwalk..."
        binwalk "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "binwalk scan failed for $base_pdf_name"
    else
         echo -e "\n=== Binwalk Scan (Skipped) ===" >> "$REPORT_FILE"
    fi

    # --- Validation & Signature ---
    echo -e "\n=== PDFCPU Validation (Strict Mode) ===" >> "$REPORT_FILE"
    pdfcpu validate -mode strict "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "pdfcpu validate failed for $base_pdf_name (may indicate issues)"

    echo -e "\n=== PDF Signature Check (pdfsig) ===" >> "$REPORT_FILE"
    pdfsig "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE"
    local pdfsig_exit_code=$?
     if [[ $pdfsig_exit_code -ne 0 ]] && [[ $pdfsig_exit_code -ne 1 ]] && [[ $pdfsig_exit_code -ne 2 ]]; then
        # Exit codes 1 (no sigs) and 2 (some invalid) are common, only log others as failure
        log_msg "WARN" "pdfsig check failed for $base_pdf_name (Code: $pdfsig_exit_code)"
    fi

    # --- QPDF Deep Grep (Optional) ---
    if [[ "$RUN_QDF_GREP" == true ]]; then
        echo -e "\n=== Deep Grep in Uncompressed Streams (Keywords: ${KEYWORDS_GREP}) ===" >> "$REPORT_FILE"
        local unpacked_pdf="$out_dir/unpacked_temp_${base_pdf_name}.pdf"
        log_debug "Running qpdf to uncompress streams..."
        qpdf --qdf --stream-data=uncompress "$pdf_file" "$unpacked_pdf" 2>> "$LOG_FILE"
        if [[ $? -eq 0 ]]; then
            log_debug "Grepping unpacked PDF for '$KEYWORDS_GREP'..."
            # Use LC_ALL=C here too for grep robustness
            LC_ALL=C grep -Eahi "$KEYWORDS_GREP" "$unpacked_pdf" >> "$REPORT_FILE" 2>> "$LOG_FILE"
            echo "[INFO] Grep finished on unpacked streams (if any keywords matched)." >> "$REPORT_FILE"
            rm -f "$unpacked_pdf" # Clean up temp file
            log_debug "Removed temporary unpacked PDF: $unpacked_pdf"
        else
            log_msg "WARN" "qpdf unpack failed for $base_pdf_name (Exit code: $?). Skipping deep grep."
            echo "[WARN] qpdf unpack failed. Skipping deep grep." >> "$REPORT_FILE"
        fi
    else
        echo -e "\n=== Deep Grep in Uncompressed Streams (Skipped) ===" >> "$REPORT_FILE"
    fi

    # --- Other Tools ---
    echo -e "\n=== PDFGrep (Keywords: ${KEYWORDS_GREP}) ===" >> "$REPORT_FILE"
    pdfgrep -i -e "$KEYWORDS_GREP" "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "pdfgrep failed for $base_pdf_name"

    echo -e "\n=== PDF Separate Pages ===" >> "$REPORT_FILE"
    local pages_dir="$out_dir/${base_pdf_name}_pages"
    mkdir -p "$pages_dir"
    pdfseparate "$pdf_file" "$pages_dir/page-%d.pdf" 2>> "$LOG_FILE"
    if [[ $? -eq 0 ]]; then
        local num_pages=$(ls -1 "$pages_dir" | wc -l)
        echo "[INFO] Pages separated ($num_pages pages) into: $pages_dir" >> "$REPORT_FILE"
    else
        log_msg "WARN" "pdfseparate failed for $base_pdf_name"
        echo "[WARN] Failed to separate pages." >> "$REPORT_FILE"
    fi

    if [[ "$RUN_PDFCRACK" == true ]]; then
        echo -e "\n=== PDFCrack Preview (Check if Encrypted) ===" >> "$REPORT_FILE"
        log_debug "Checking encryption and running pdfcrack preview..."
        local is_encrypted=$(pdfinfo "$pdf_file" 2>> "$LOG_FILE" | awk '/Encrypted:/ {print $2}')
        if [[ "$is_encrypted" == "yes" ]]; then
            echo "[INFO] PDF detected as encrypted by pdfinfo. Running pdfcrack preview..." >> "$REPORT_FILE"
            pdfcrack -f "$pdf_file" -n -c abcdef1234567890 >> "$REPORT_FILE" 2>> "$LOG_FILE" || log_msg "WARN" "pdfcrack failed for $base_pdf_name"
        else
             echo "[INFO] PDF not detected as encrypted by pdfinfo. Skipping pdfcrack." >> "$REPORT_FILE"
        fi
    else
        echo -e "\n=== PDFCrack Preview (Skipped) ===" >> "$REPORT_FILE"
    fi

    # --- HTML Output ---
    echo -e "\n=== PDFToHTML Conversion Attempt ===" >> "$REPORT_FILE"
    local html_dir="$out_dir/${base_pdf_name}_html_output"
    mkdir -p "$html_dir"
    pdftohtml "$pdf_file" "$html_dir/$base_pdf_name" 2>> "$LOG_FILE"
    if [[ $? -eq 0 ]]; then
        echo "[INFO] HTML conversion attempted. Output (if any) in: $html_dir" >> "$REPORT_FILE"
    else
        log_msg "WARN" "pdftohtml failed for $base_pdf_name"
        echo "[WARN] pdftohtml conversion failed." >> "$REPORT_FILE"
    fi

    # --- PDFCPU Metadata Extraction ---
     echo -e "\n=== PDFCPU Metadata Extraction ===" >> "$REPORT_FILE"
     local pdfcpu_meta_dir="$out_dir/pdfcpu_metadata"
     mkdir -p "$pdfcpu_meta_dir"
      pdfcpu extract -m meta "$pdf_file" "$pdfcpu_meta_dir" >> "$REPORT_FILE" 2>> "$LOG_FILE"

     if [[ $? -eq 0 ]]; then
        echo "[INFO] pdfcpu metadata extracted to: $pdfcpu_meta_dir" >> "$REPORT_FILE"
    else
        log_msg "WARN" "pdfcpu extract metadata failed for $base_pdf_name"
        echo "[WARN] pdfcpu metadata extraction failed." >> "$REPORT_FILE"
    fi

    echo -e "\n--- End of Scan for: $pdf_file ---" >> "$REPORT_FILE"
}

process_pdf() {
    local pdf_file="$1"
    # Add debug log at the very start of the function
    log_debug "Entered process_pdf with file: '$pdf_file'"

    # Use '-s' for pdf suffix removal, robust for ".pdf" vs ".PDF" etc.
    # Also handle potential paths in the name using basename last
    local base_name_with_path=$(basename -s .pdf -s .PDF "$pdf_file")
    local base_name=$(basename "$base_name_with_path")

    # Calculate OUTDIR relative to the main RUN_OUTPUT_DIR
    local out_dir="$RUN_OUTPUT_DIR/$base_name"

    log_debug "Calculated base_name: '$base_name'"
    log_debug "Calculated out_dir: '$out_dir'"

    # Attempt to create directory
    log_debug "Attempting to create output directory '$out_dir'"
    mkdir -p "$out_dir"
    local mkdir_exit_code=$? # Capture exit code immediately
    log_debug "mkdir exit code: $mkdir_exit_code"

    if [[ $mkdir_exit_code -ne 0 ]]; then
        log_msg "ERROR" "Failed to create output directory '$out_dir'. Check permissions and path validity for base '$RUN_OUTPUT_DIR' and name '$base_name'."
        # Also log error to the detailed execution log file
        echo "[ERROR] mkdir -p \"$out_dir\" failed with exit code $mkdir_exit_code" >> "$LOG_FILE"
        return 1 # Stop processing this file if dir creation fails
    fi
    log_msg "INFO" "Successfully created output directory: '$out_dir'" # Log success
    log_debug "Output directory should now exist: '$out_dir'"

    # --- Calculate Hash (and log) ---
    log_msg "INFO" "Calculating hash for: $base_name"
    log_debug "Running shasum command for $pdf_file"
    # Append hash to report, log errors only to detailed log
    if ! shasum -a 256 "$pdf_file" >> "$REPORT_FILE" 2>> "$LOG_FILE"; then
         log_msg "WARN" "Failed to calculate SHA256 hash for '$base_name'"
         log_debug "shasum failed for $pdf_file"
    fi

    # --- Call Sub-functions ---
    log_msg "INFO" "Generating HTML report for: $base_name"
    log_debug "Calling generate_html_report for '$pdf_file' into '$out_dir'"
    generate_html_report "$pdf_file" "$out_dir"

    log_msg "INFO" "Running forensic scan for: $base_name"
    log_debug "Calling run_forensic_scan for '$pdf_file' into '$out_dir'"
    run_forensic_scan "$pdf_file" "$out_dir"

    log_msg "INFO" "Finished processing: $base_name"
    log_debug "Exiting process_pdf for file: '$pdf_file'"
    # Add a separator in the main report for clarity between files
    echo -e "\n#############################################################################\n" >> "$REPORT_FILE"
}

# --- Main Execution Logic ---

main() {
    # Ensure script isn't run with sudo unnecessarily
    if [[ "$(id -u)" -eq 0 ]]; then
       log_msg "WARN" "Running this script as root (sudo) is generally not recommended."
    fi

    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <file.pdf | folder> [<file.pdf | folder> ...]" >&2
        echo "Example: $0 document.pdf /path/to/scans/" >&2
        exit 1
    fi

    # Check dependencies first
    check_dependencies

    log_msg "INFO" "Processing $# input path(s)... Output base: $RUN_OUTPUT_DIR"

    local processed_files_count=0
    local error_count=0
    for input_path in "$@"; do
        log_debug "Processing input argument: $input_path"
        if [[ -d "$input_path" ]]; then
            log_msg "INFO" "Input is a directory, searching for PDF files in: $input_path"
            # Use find with print0 and read -d '' for safety with filenames
            # Also handle potential errors during find or read
            while IFS= read -r -d $'\0' pdf_file; do
                if [[ -n "$pdf_file" ]]; then # Ensure filename is not empty
                     log_debug "Found PDF in directory: $pdf_file"
                     process_pdf "$pdf_file"
                     if [[ $? -ne 0 ]]; then error_count=$((error_count + 1)); fi
                     processed_files_count=$((processed_files_count + 1))
                fi
            done < <(find "$input_path" -type f \( -iname "*.pdf" \) -print0 2>> "$LOG_FILE")

        elif [[ -f "$input_path" ]] && [[ "${input_path##*.}" =~ ^[pP][dD][fF]$ ]]; then
            log_msg "INFO" "Processing PDF file: $input_path"
            process_pdf "$input_path"
            if [[ $? -ne 0 ]]; then error_count=$((error_count + 1)); fi
            processed_files_count=$((processed_files_count + 1))
        elif [[ -f "$input_path" ]]; then
            log_msg "WARN" "Input '$input_path' is a file but not a PDF (*.pdf). Skipping."
        elif [[ -e "$input_path" ]]; then
             log_msg "WARN" "Input '$input_path' exists but is not a regular file or directory. Skipping."
        else
            log_msg "ERROR" "Input '$input_path' not found. Skipping."
            error_count=$((error_count + 1))
        fi
    done

    log_msg "INFO" "Script finished. Processed $processed_files_count PDF file(s) with $error_count error(s) during processing."
    log_msg "INFO" "Consolidated report: $REPORT_FILE"
    log_msg "INFO" "Detailed execution log: $LOG_FILE"
    log_msg "INFO" "Individual file outputs are in subdirectories within: $RUN_OUTPUT_DIR"

    # Optionally open the main output directory at the end (macOS)
    if [[ "$(uname)" == "Darwin" ]]; then
        # Check if directory actually contains anything beyond logs before opening
        if [ "$(ls -A "$RUN_OUTPUT_DIR" | grep -v consolidated_forensic_report.txt | grep -v execution_details.log)" ]; then
            log_msg "INFO" "Opening output directory: $RUN_OUTPUT_DIR"
            open "$RUN_OUTPUT_DIR"
        else
            log_msg "INFO" "Output directory is empty or only contains log/report files. Not opening."
        fi
    fi
}

# --- Run Main Function ---
# Use pipefail to catch errors in pipelines if needed, e.g., in find | while
# set -o pipefail
main "$@"

exit 0
