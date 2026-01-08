#!/bin/bash

# Check if a file name is provided
if [ -z "$1" ]; then
    echo "❌ Error: No PDF file provided!"
    echo "Usage: ./analyze_pdf_advanced.sh <pdf_file>"
    exit 1
fi

# Define PDF file from command line argument
PDF_FILE="$1"

# Create output directory with dynamic name based on input file
OUTPUT_DIR="out_$(basename "$PDF_FILE" .pdf)"
mkdir -p "$OUTPUT_DIR"

# Extract metadata using ExifTool
exiftool -a -G1 -s "$PDF_FILE" > "$OUTPUT_DIR/exiftool_output.txt"

# Check internal PDF structure using QPDF
qpdf --check "$PDF_FILE" > "$OUTPUT_DIR/qpdf_check.txt" 2>&1

# Extract PDF structure with XRef information
qpdf --show-xref "$PDF_FILE" > "$OUTPUT_DIR/xref_analysis.txt"

# Dump raw PDF structure for analysis (may contain hidden objects)
qpdf --object-streams=disable --qdf "$PDF_FILE" "$OUTPUT_DIR/pdf_raw_structure.pdf"

# Check for orphaned objects (objects without references)
qpdf --show-object 1-z "$PDF_FILE" > "$OUTPUT_DIR/pdf_objects_analysis.txt"

# Extract all embedded images from the PDF
pdfimages -all "$PDF_FILE" "$OUTPUT_DIR/pdf_images"

# Extract raw streams (useful for detecting hidden text inside images)
pdfdetach -saveall "$PDF_FILE" -o "$OUTPUT_DIR/"

# Extract embedded fonts (sometimes custom fonts store altered text)
pdffonts "$PDF_FILE" > "$OUTPUT_DIR/pdf_fonts.txt"

# Extract and analyze page content streams (useful for detecting manipulated text)
for i in $(seq 1 $(pdfinfo "$PDF_FILE" | grep Pages | awk '{print $2}')); do
    pdftotext -f $i -l $i -raw "$PDF_FILE" "$OUTPUT_DIR/page_${i}_raw.txt"
done

# Check for embedded JavaScript (PDFs can contain scripts to manipulate content)
pdfinfo "$PDF_FILE" | grep JavaScript > "$OUTPUT_DIR/pdf_javascript.txt"

# Check for alternative metadata entries (/Info vs /Metadata objects)
exiftool -X "$PDF_FILE" > "$OUTPUT_DIR/metadata_raw.xml"

# Advanced PDF analysis using peepdf
peepdf -i -f "$PDF_FILE" > "$OUTPUT_DIR/peepdf_analysis.txt"

# Parsing raw objects using pdf-parser.py
pdf-parser.py "$PDF_FILE" > "$OUTPUT_DIR/pdf_parser_output.txt"

# Detecting orphaned objects and indirect references
pdf-objects.py "$PDF_FILE" > "$OUTPUT_DIR/pdf_objects_details.txt"

# Zip results
zip -r "${OUTPUT_DIR}.zip" "$OUTPUT_DIR/"

echo "🔍 Advanced analysis complete! File '${OUTPUT_DIR}.zip' is ready for upload."
