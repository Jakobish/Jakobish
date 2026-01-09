#!/usr/bin/env python3
#############################################
# Script: pdforensic_cli.py
# Purpose:
#   A simple and clean CLI tool for forensic analysis of PDF files.
#   It processes a single PDF or all PDFs in a folder, extracting:
#     - Metadata (pdfinfo, exiftool)
#     - Text (pdftotext)
#     - Embedded images (pdfimages)
#     - OCR output (ocrmypdf) including:
#         - Enhanced PDF with text layer
#         - Sidecar .txt file
#   Output is organized under:
#     forensic_results/<filename>_<timestamp>/
#   A summary CSV file logs all processed PDFs and their output paths.
# Notes:
#   - Can be hooked into Finder right-click or Automator
#   - All commands are run via subprocess with captured output
#############################################
import os
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
import csv

# ========== CONFIGURATION ==========
OUTPUT_BASE = Path("forensic_results")
LANGUAGES = "heb+eng"
DPI = 600

# ========== UTILS ==========
def run_cmd(cmd, logfile=None, cwd=None):
    print(f"\n🔧  Running: {cmd}\n")
    with open(logfile, 'w') if logfile else subprocess.DEVNULL as f:
        result = subprocess.run(cmd, shell=True, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        print(f"❌  Command failed: {cmd}")
    return result

def create_dir_structure(base_dir):
    ocr_dir = base_dir / "ocr"
    images_dir = base_dir / "images"
    text_dir = base_dir / "text"
    meta_dir = base_dir / "meta"
    for d in [ocr_dir, images_dir, text_dir, meta_dir]:
        d.mkdir(parents=True, exist_ok=True)
    return ocr_dir, images_dir, text_dir, meta_dir

# ========== MAIN PROCESS ==========
def process_pdf(pdf_path: Path):
    print(f"\n🔍  Processing {pdf_path.name}")
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    safe_name = pdf_path.stem.replace(' ', '_')
    base_dir = OUTPUT_BASE / f"{safe_name}_{timestamp}"
    base_dir.mkdir(parents=True, exist_ok=True)

    ocr_dir, images_dir, text_dir, meta_dir = create_dir_structure(base_dir)

    # Copy original
    shutil.copy(pdf_path, base_dir / "original.pdf")

    # Extract metadata
    run_cmd(f'pdfinfo "{pdf_path}"', meta_dir / "pdfinfo.txt")
    run_cmd(f'exiftool "{pdf_path}"', meta_dir / "exiftool.txt")

    # Extract text
    run_cmd(f'pdftotext "{pdf_path}" "{text_dir}/text.txt"', text_dir / "pdftotext_log.txt")

    # Extract images
    run_cmd(f'pdfimages -png "{pdf_path}" "{images_dir}/img"', images_dir / "pdfimages_log.txt")

    # OCR to PDF & HOCR + TXT (black & white, high DPI)
    run_cmd(
        f'ocrmypdf --force-ocr --output-type pdf --rotate-pages --deskew -l {LANGUAGES} '
        f'--image-dpi {DPI} --sidecar "{ocr_dir}/ocr.txt" "{pdf_path}" "{ocr_dir}/ocr.pdf"',
        ocr_dir / "ocrmypdf_log.txt"
    )

    return {
        "filename": pdf_path.name,
        "timestamp": timestamp,
        "path": str(base_dir)
    }

# ========== ENTRY ==========
def main():
    import sys
    input_path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if not input_path or not input_path.exists():
        print("❌  Please provide a valid file or folder path.")
        return

    OUTPUT_BASE.mkdir(exist_ok=True)
    csv_file = OUTPUT_BASE / f"summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    rows = []

    pdf_files = [input_path] if input_path.is_file() else list(input_path.glob("*.pdf"))
    for pdf in pdf_files:
        info = process_pdf(pdf)
        rows.append(info)

    # Write summary CSV
    with open(csv_file, "w", newline='') as f:
        writer = csv.DictWriter(f, fieldnames=["filename", "timestamp", "path"])
        writer.writeheader()
        writer.writerows(rows)

    print(f"\n📄  Summary written to: {csv_file}")

if __name__ == "__main__":
    main()
