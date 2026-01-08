#!/bin/bash
# forensic.sh
# This script processes all PDF files in the current directory and extracts as much available information as possible.
# It runs OCR (Tesseract), uncompresses the PDF (qpdf), extracts text/HTML/cleaned PDF/info (mutool), extracts metadata (exiftool),
# creates a hex dump (xxd), extracts images (pdfimages), and extracts embedded objects (mutool extract).
#
# The output is organized in a hierarchical structure:
#   MAIN_OUTPUT_DIR -> per–PDF folder (by base name) -> timestamped run folder ->
#      tool-specific subdirectories (ocr, mutool, qpdf, exiftool, hex, pdfimages, mutool_extract)
#
# For each PDF file, a Markdown report is generated with all the extracted information.
# This Markdown report is then converted to a PDF (using pandoc) and merged with the original PDF
# to produce a composite PDF that contains both the original content and the appended analysis.
#
# Required tools:
#   - mutool, qpdf, exiftool, xxd, tesseract, pdfimages, pandoc (for PDF report generation)
#
# Author: [Your Name]
# Date: [Current Date]

# Default configuration
MAIN_OUTPUT_DIR="./pdfsrc"
PARALLEL_JOBS=1
VERBOSE=0
start_time=$(date +%s)

# Function to show usage
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    -h, --help              Show this help message
    -o, --output DIR        Set output directory (default: $MAIN_OUTPUT_DIR)
    -j, --jobs N           Number of parallel jobs (default: 1)
    -v, --verbose          Enable verbose output
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -o|--output)
            MAIN_OUTPUT_DIR="$2"
            shift 2
            ;;
        -j|--jobs)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Function for logging
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [[ $VERBOSE -eq 1 ]] || [[ $level == "ERROR" ]]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# Check that all required tools are installed
required_tools=(mutool qpdf exiftool xxd tesseract pdfimages pandoc)
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        log "ERROR" "$tool is not installed. Please install it."
        exit 1
    fi
done

# Enable nullglob so that globs return an empty list if no matches are found
shopt -s nullglob

# Create output directory
if ! mkdir -p "$MAIN_OUTPUT_DIR"; then
    log "ERROR" "Failed to create output directory: $MAIN_OUTPUT_DIR"
    exit 1
fi

# Find all PDF files in the current directory
pdf_files=(*.pdf)
if [ ${#pdf_files[@]} -eq 0 ]; then
    log "INFO" "No PDF files found in the current directory."
    exit 0
fi

# Function to process a single PDF file
process_pdf() {
    local file="$1"
    local base_name
    base_name=$(basename "$file" .pdf)
    
    [[ $VERBOSE -eq 1 ]] && log "INFO" "Processing file: $file"

    # Create a folder for the PDF (by its base name)
    local file_dir="${MAIN_OUTPUT_DIR}/${base_name}"
    mkdir -p "$file_dir"

    # Create a run subfolder with a timestamp
    local timestamp
    timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local run_dir="${file_dir}/${timestamp}"
    mkdir -p "$run_dir"

    # Create tool-specific subdirectories
    local ocr_dir="${run_dir}/ocr"
    local mutool_dir="${run_dir}/mutool"
    local qpdf_dir="${run_dir}/qpdf"
    local exiftool_dir="${run_dir}/exiftool"
    local hex_dir="${run_dir}/hex"
    local pdfimages_dir="${run_dir}/pdfimages"
    local extract_dir="${run_dir}/mutool_extract"
    mkdir -p "$ocr_dir" "$mutool_dir" "$qpdf_dir" "$exiftool_dir" "$hex_dir" "$pdfimages_dir" "$extract_dir"

    # Run all the processing steps with proper error handling
    {
        [[ $VERBOSE -eq 1 ]] && log "INFO" "Running Tesseract OCR for $file..."
        tesseract "$file" "${ocr_dir}/${base_name}_ocr" --psm 3 -c preserve_interword_spaces=1 pdf || log "ERROR" "Failed OCR PDF on $file"
        tesseract "$file" "${ocr_dir}/${base_name}_ocr_text" --psm 3 -c preserve_interword_spaces=1 txt || log "ERROR" "Failed OCR Text on $file"
        tesseract "$file" "${ocr_dir}/${base_name}_ocr_hocr" --psm 3 -c preserve_interword_spaces=1 hocr || log "ERROR" "Failed OCR HOCR on $file"

        [[ $VERBOSE -eq 1 ]] && log "INFO" "Running qpdf for $file..."
        qpdf --qdf --object-streams=disable "$file" "${qpdf_dir}/${base_name}_qdf.pdf" || log "ERROR" "Failed qpdf processing on $file"

        [[ $VERBOSE -eq 1 ]] && log "INFO" "Running mutool for $file..."
        mutool draw -F txt -o "${mutool_dir}/${base_name}_text.txt" "$file" || log "ERROR" "Failed text extraction with mutool from $file"
        mutool draw -F html -o "${mutool_dir}/${base_name}_output.html" "$file" || log "ERROR" "Failed HTML extraction with mutool from $file"
        mutool clean -d "$file" "${mutool_dir}/${base_name}_cleaned.pdf" || log "ERROR" "Failed PDF cleaning with mutool from $file"
        mutool info "$file" > "${mutool_dir}/${base_name}_info.txt" || log "ERROR" "Failed info extraction with mutool from $file"

        [[ $VERBOSE -eq 1 ]] && log "INFO" "Running exiftool for $file..."
        exiftool -json "$file" > "${exiftool_dir}/${base_name}_metadata.json" || log "ERROR" "Failed metadata extraction from $file"

        [[ $VERBOSE -eq 1 ]] && log "INFO" "Creating hex dump for $file..."
        xxd "$file" > "${hex_dir}/${base_name}_hex_dump.txt" || log "ERROR" "Failed creating hex dump for $file"

        [[ $VERBOSE -eq 1 ]] && log "INFO" "Running pdfimages for $file..."
        pdfimages -all "$file" "${pdfimages_dir}/${base_name}_images" || log "ERROR" "Failed extracting images from $file"

        [[ $VERBOSE -eq 1 ]] && log "INFO" "Running mutool extract for $file..."
        pushd "$extract_dir" > /dev/null || log "ERROR" "Failed to change directory for mutool extract"
        mutool extract "$OLDPWD/$file" || log "ERROR" "Failed extracting objects from $file"
        popd > /dev/null || true

        # Create Markdown report
        [[ $VERBOSE -eq 1 ]] && log "INFO" "Creating report for $file..."
        markdown_file="${run_dir}/${base_name}_report.md"
        {
            echo "# PDF Forensics Report - $base_name"
            echo "Date: $timestamp"
            echo ""
            echo "## Original File"
            echo "[Download Original PDF](../../$file)"
            echo ""
            echo "## OCR Output"
            echo "**Searchable PDF:** [Download OCR PDF](./ocr/${base_name}_ocr.pdf)"
            echo ""
            echo "### OCR Text"
            echo '```'
            cat "${ocr_dir}/${base_name}_ocr_text.txt" 2>/dev/null
            echo '```'
            echo ""
            echo "### OCR HOCR"
            echo "[View HOCR Output](./ocr/${base_name}_ocr_hocr.html)"
            echo ""
            echo "## Extracted Text (mutool)"
            echo '```'
            cat "${mutool_dir}/${base_name}_text.txt" 2>/dev/null
            echo '```'
            echo ""
            echo "## PDF Info (mutool)"
            echo '```'
            cat "${mutool_dir}/${base_name}_info.txt" 2>/dev/null
            echo '```'
            echo ""
            echo "## Hex Dump"
            echo "[Download Hex Dump](./hex/${base_name}_hex_dump.txt)"
            echo ""
            echo "## Metadata (exiftool)"
            echo '```json'
            cat "${exiftool_dir}/${base_name}_metadata.json" 2>/dev/null
            echo '```'
            echo ""
            echo "## PDF Structure (qpdf)"
            echo "[Download Processed PDF](./qpdf/${base_name}_qdf.pdf)"
            echo ""
            echo "## HTML Output (mutool)"
            echo "[View HTML Output](./mutool/${base_name}_output.html)"
            echo ""
            echo "## Extracted Images (pdfimages)"
            echo "Images extracted can be found in the [pdfimages directory](./pdfimages)."
            echo ""
            echo "## Extracted Objects (mutool)"
            echo "Extracted objects can be found in the [mutool_extract directory](./mutool_extract)."
        } > "$markdown_file"

        # Convert the Markdown report to PDF using pandoc
        report_pdf="${run_dir}/${base_name}_report.pdf"
        if pandoc "$markdown_file" -o "$report_pdf" --pdf-engine=xelatex -V geometry:margin=1in; then
            [[ $VERBOSE -eq 1 ]] && log "INFO" "Report PDF created: $report_pdf"
        else
            log "ERROR" "Error converting Markdown to PDF."
        fi

    # Merge the original PDF and the report PDF into a composite PDF
    composite_pdf="${run_dir}/${base_name}_composite.pdf"

    # Check if both the original PDF and the report PDF exist
    if [[ -f "$file" && -f "$report_pdf" ]]; then
        if qpdf --empty --pages "$file" "$report_pdf" -- "$composite_pdf"; then
            [[ $VERBOSE -eq 1 ]] && log "INFO" "Composite PDF created: $composite_pdf"
        else
            log "ERROR" "Error merging PDFs for $file and $report_pdf."
        fi
    else
        log "ERROR" "One or both of the input PDFs do not exist. Original: $file, Report: $report_pdf"
    fi
    } || log "ERROR" "Failed processing $file"
}

# Process each PDF file
for pdf_file in "${pdf_files[@]}"; do
    process_pdf "$pdf_file"
done

# Process completion message
log "INFO" "All files processed. Output available in '$MAIN_OUTPUT_DIR'"

# Calculate execution time
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

# Format the elapsed time more readably
if [ $elapsed_time -gt 60 ]; then
    minutes=$((elapsed_time / 60))
    seconds=$((elapsed_time % 60))
    time_message="${minutes}m ${seconds}s"
else
    time_message="${elapsed_time}s"
fi

# Final status messages with improved formatting
log "INFO" "🏁 Processing completed in $time_message"
log "INFO" "📂 All results are saved in: $MAIN_OUTPUT_DIR"