#############################################
# Script: forensic_pdf_analysiv2s.sh
# Purpose:
#   This advanced Bash script performs deep forensic analysis on all PDF files 
#   in the current directory and organizes results in structured subfolders.
# Features:
#   - Validates required tools: mutool, qpdf, exiftool, xxd, tesseract, pdfimages, pandoc
#   - For each PDF, it:
#       - Runs OCR (PDF, TXT, HOCR) using Tesseract
#       - Converts to QDF format with qpdf
#       - Extracts text, HTML, cleaned PDF, and info via mutool
#       - Extracts metadata using exiftool (JSON)
#       - Creates hex dump using xxd
#       - Extracts images with pdfimages
#       - Extracts embedded objects with mutool extract
#       - Compiles all findings into a Markdown report
#       - Converts report to PDF and merges it with original into composite PDF
# Output:
#   - Results are saved under: PDF_Organizer_Output/<filename>/<timestamp>/
#   - Includes OCR, metadata, structure, images, hex, and full report
#!/bin/bash
# pdf_organizer_composite.sh - Advanced PDF processing and forensic analysis

# Required tools
required_tools=(mutool qpdf exiftool xxd tesseract pdfimages pandoc)
missing_tools=()
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
        missing_tools+=("$tool")
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "Error: The following tools are missing: ${missing_tools[*]}" >&2
    echo "Please install the missing tools before proceeding."
    exit 1
fi

# Enable nullglob to avoid issues with missing files
shopt -s nullglob

# Check explicitly if any PDF files exist before processing
if ! ls *.pdf &>/dev/null; then
    echo "No PDF files found in the current directory."
    exit 0
fi

# Define output directory
MAIN_OUTPUT_DIR="PDF_Organizer_Output"
mkdir -p "$MAIN_OUTPUT_DIR"

# Process each PDF file
for file in *.pdf; do
    base_name=$(basename "$file" .pdf)
    echo "Processing file: $file"

    file_dir="${MAIN_OUTPUT_DIR}/${base_name}"
    mkdir -p "$file_dir"

    timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    run_dir="${file_dir}/${timestamp}"
    for dir in ocr mutool qpdf exiftool hex pdfimages mutool_extract; do
        if [[ ! -d "$run_dir/$dir" ]]; then
            mkdir -p "$run_dir/$dir"
        fi
    done

    echo "  Running Tesseract OCR..."
    tesseract "$file" "${run_dir}/ocr/${base_name}_ocr" --psm 3 -c preserve_interword_spaces=1 pdf || true
    tesseract "$file" "${run_dir}/ocr/${base_name}_ocr_text" --psm 3 -c preserve_interword_spaces=1 txt || true
    tesseract "$file" "${run_dir}/ocr/${base_name}_ocr_hocr" --psm 3 -c preserve_interword_spaces=1 hocr || true

    echo "  Running qpdf..."
    qpdf --qdf --object-streams=disable "$file" "${run_dir}/qpdf/${base_name}_qdf.pdf" || true

    echo "  Running mutool..."
    mutool draw -F txt -o "${run_dir}/mutool/${base_name}_text.txt" "$file" || true
    mutool draw -F html -o "${run_dir}/mutool/${base_name}_output.html" "$file" || true
    mutool clean -d "$file" "${run_dir}/mutool/${base_name}_cleaned.pdf" || true
    mutool info "$file" > "${run_dir}/mutool/${base_name}_info.txt" || true

    echo "  Running exiftool..."
    exiftool -json "$file" > "${run_dir}/exiftool/${base_name}_metadata.json" || true

    echo "  Creating hex dump..."
    xxd "$file" > "${run_dir}/hex/${base_name}_hex_dump.txt" || true

    echo "  Running pdfimages..."
    pdfimages -all "$file" "${run_dir}/pdfimages/${base_name}_images" || true

    echo "  Running mutool extract..."
    pushd "${run_dir}/mutool_extract" > /dev/null
    if ! mutool extract "$OLDPWD/$file"; then
        echo "Error: Failed to extract objects from $file" | tee -a "${MAIN_OUTPUT_DIR}/error.log" >&2
    fi
    popd > /dev/null

    markdown_file="${run_dir}/${base_name}_report.md"
    {
        echo "# PDF Analysis Report - $base_name"
        echo "Date: $timestamp"
        echo ""
        echo "## OCR Output"
        echo "**Searchable PDF:** [OCR PDF](./ocr/${base_name}_ocr.pdf)"
        echo "### OCR Text"
        echo '```'
        cat "${run_dir}/ocr/${base_name}_ocr_text.txt" 2>/dev/null
        echo '```'
        echo "## Extracted Text (mutool)"
        echo '```'
        cat "${run_dir}/mutool/${base_name}_text.txt" 2>/dev/null
        echo '```'
        echo "## PDF Info (mutool)"
        echo '```'
        cat "${run_dir}/mutool/${base_name}_info.txt" 2>/dev/null
        echo '```'
        echo "## Hex Dump"
        echo "[Download Hex Dump](./hex/${base_name}_hex_dump.txt)"
        echo "## Metadata (exiftool)"
        echo '```json'
        cat "${run_dir}/exiftool/${base_name}_metadata.json" 2>/dev/null
        echo '```'
    } > "$markdown_file"

    report_pdf="${run_dir}/${base_name}_report.pdf"
    echo "  Converting Markdown report to PDF..."
    pandoc "$markdown_file" -o "$report_pdf" --pdf-engine=xelatex -V geometry:margin=1in || true

    composite_pdf="${run_dir}/${base_name}_composite.pdf"
    if [[ -f "$file" && -f "$report_pdf" ]]; then
        echo "  Merging PDFs..."
        qpdf --empty --pages "$file" "$report_pdf" -- "$composite_pdf" || true
        echo "    Composite PDF created: $composite_pdf"
    else
        echo "    Skipping merge, one of the files is missing." | tee -a "${MAIN_OUTPUT_DIR}/error.log" >&2
    fi

    echo "Done processing: $file"
done

echo "All files processed. Output available in '$MAIN_OUTPUT_DIR'."

