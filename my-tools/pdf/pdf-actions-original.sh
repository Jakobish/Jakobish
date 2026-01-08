#!/bin/bash
#############################################
# Script: pdf-actions-original.sh
# Purpose:
#   This Automator-compatible shell script generates an HTML report 
#   from one or more PDF files or folders containing PDFs.
#   It:
#     - Iterates through selected PDF files or folders via Finder's right-click
#     - Extracts metadata using exiftool
#     - Extracts PDF structure and document info using pdfinfo
#     - Wraps the outputs into an HTML file styled with minimal CSS
#     - Opens the generated report in the default HTML viewer (TextEdit or browser)
# Output:
#   - The report is saved to: ~/Desktop/pdf_report_<timestamp>.html
#############################################

# Extend PATH for Automator environment
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

TMPFILE="$HOME/Desktop/pdf_report_$(date +%s).html"

{
  echo "<html><head><meta charset='UTF-8'>"
  echo "<style>"
  echo "body { font-family: monospace; background: #f9f9f9; padding: 20px; }"
  echo "h2 { background: #333; color: white; padding: 5px; }"
  echo "pre { background: #eee; border: 1px solid #ccc; padding: 10px; }"
  echo "</style><title>PDF Report</title></head><body>"

  for path in "$@"; do
    if [[ -d "$path" ]]; then
      # Handle folder: scan all PDF files in it
      find "$path" -type f -iname "*.pdf" | while read -r file; do
        echo "<h2>📄 PDF Metadata for $file</h2><pre>"
        if ! exiftool "$file"; then
          echo "[⚠️] Failed to read metadata with exiftool."
        fi
        echo "</pre>"
        echo "<h2>📄 PDF Info for $file</h2><pre>"
        if ! pdfinfo "$file"; then
          echo "[⚠️] Failed to read info with pdfinfo."
        fi
        echo "</pre>"
      done
    elif [[ "$path" == *.pdf ]]; then
      # Handle individual PDF file
      echo "<h2>📄 PDF Metadata for $path</h2><pre>"
      if ! exiftool "$path"; then
        echo "[⚠️] Failed to read metadata with exiftool."
      fi
      echo "</pre>"
      echo "<h2>📄 PDF Info for $path</h2><pre>"
      if ! pdfinfo "$path"; then
        echo "[⚠️] Failed to read info with pdfinfo."
      fi
      echo "</pre>"
    fi
  done

  echo "</body></html>"
} > "$TMPFILE"

open "$TMPFILE"