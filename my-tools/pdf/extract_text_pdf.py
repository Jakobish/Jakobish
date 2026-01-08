#!/usr/bin/env python3
#
# Script: extract_text_pdf.py
# Purpose: Helper script for analyze_pdfs_v2.sh to extract text from a PDF
#          using the pdfplumber library.
# Usage: python3 extract_text_pdp.py <path_to_pdf_file>
# Output: Prints extracted text to stdout, errors to stderr.
# Requires: pip3 install pdfplumber
#
#############################################################################

import pdfplumber
import sys
import argparse
import os

def extract_text(pdf_path):
    """Extracts text from all pages of a PDF using pdfplumber."""
    if not os.path.isfile(pdf_path):
        print(f"[PYTHON_ERROR] PDF file not found or is not a file: {pdf_path}", file=sys.stderr)
        sys.exit(1)

    text_content = ""
    page_count = 0
    file_size = os.path.getsize(pdf_path)
    print(f"--- PDFPlumber Processing Start: {os.path.basename(pdf_path)} (Size: {file_size} bytes) ---", file=sys.stderr) # Log start to stderr

    try:
        with pdfplumber.open(pdf_path) as pdf:
            page_count = len(pdf.pages)
            if page_count == 0:
                print("[INFO] PDFPlumber: Document has 0 pages.")
                print(f"--- PDFPlumber Processing End: {os.path.basename(pdf_path)} ---", file=sys.stderr)
                sys.exit(0) # Not an error if PDF truly has no pages

            for i, page in enumerate(pdf.pages):
                # Add page separator for clarity
                text_content += f"--- PDFPlumber Page {i+1} of {page_count} ---\n"
                try:
                    # Attempt to extract text from the current page
                    page_text = page.extract_text(x_tolerance=2, y_tolerance=2) # Adjust tolerance if needed
                    text_content += page_text if page_text else "[No text extracted from this page by PDFPlumber]"
                except Exception as page_e:
                    # Log error for specific page but continue if possible
                    text_content += f"[ERROR] PDFPlumber failed to extract text from page {i+1}: {page_e}"
                    print(f"[PYTHON_ERROR] PDFPlumber failed on page {i+1} of {pdf_path}: {page_e}", file=sys.stderr)
                text_content += "\n" # Add newline after each page's content or error message

        # Print accumulated text to stdout
        print(text_content)
        print(f"--- PDFPlumber Processing End: {os.path.basename(pdf_path)} ---", file=sys.stderr) # Log end to stderr

    except Exception as e:
        print(f"\n[ERROR] PDFPlumber failed to open or process {pdf_path}: {e}", file=sys.stdout) # Print error to stdout for report
        print(f"[PYTHON_ERROR] PDFPlumber failed for {pdf_path}: {e}", file=sys.stderr) # Log detailed error to stderr
        sys.exit(1) # Exit with error status

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Extract text from all pages of a PDF using pdfplumber.")
    parser.add_argument("pdf_path", help="Path to the PDF file.")

    # Ensure help message is shown if no arguments are given
    if len(sys.argv) == 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    args = parser.parse_args()
    extract_text(args.pdf_path)
    sys.exit(0) # Explicitly exit with success code