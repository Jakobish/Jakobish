#!/usr/bin/env python3
#############################################
# Script: pdforensic_cli_ultimate_v2.py
# Purpose:
#   A modern CLI tool for PDF forensic analysis with structured output.
#   Features:
#     - Processes a single PDF or a folder of PDFs
#     - Extracts:
#         - Metadata (pdfinfo, exiftool)
#         - Text content (pdftotext)
#         - Embedded images (pdfimages)
#         - OCR with sidecar output (ocrmypdf)
#     - Creates organized timestamped folders:
#         - metadata/, text/, images/, ocr_output/
#     - Logs each run into a master CSV file for tracking
# Output:
#   - All outputs saved under: forensic_results/<filename>_<timestamp>/
#   - OCR outputs stored under: ocr_force/<filename>/
#   - Summary CSV: forensic_results/summary_<timestamp>.csv
#############################################

import argparse
import subprocess
import sys
import os
from pathlib import Path
from datetime import datetime
from bs4 import BeautifulSoup
import fitz  # PyMuPDF
import shutil
import csv

BANNER = """\033[1;32m
██████╗ ███████╗██████╗ ███████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗ ██████╗
██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝ ██╔══██╗██╔════╝████╗  ██║██║██╔════╝
██║  ██║█████╗  ██████╔╝█████╗  ██║  ███╗██████╔╝█████╗  ██╔██╗ ██║██║██║     
██║  ██║██╔══╝  ██╔══██╗██╔══╝  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║██║     
██████╔╝███████╗██║  ██║███████╗╚██████╔╝██║     ███████╗██║ ╚████║██║╚██████╗
╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝╚═╝ ╚═════╝
           Forensic CLI Tool for PDF Analysis ✨ by You & GPT
\033[0m"""

OUTPUT_DIR = Path("forensic_results")
OCR_DIR = Path("ocr_force")
CSV_FILE = OUTPUT_DIR / f"summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"

def run_cmd(cmd, out_path):
    with open(out_path, "w") as f:
        subprocess.run(cmd, shell=True, stdout=f, stderr=subprocess.STDOUT)

def extract_metadata(pdf, outdir):
    run_cmd(f'pdfinfo "{pdf}"', outdir / "pdf_info.txt")
    run_cmd(f'exiftool "{pdf}"', outdir / "exif_metadata.txt")

def extract_text(pdf, outdir):
    run_cmd(f'pdftotext "{pdf}" "{outdir}/text.txt"', outdir / "pdftotext_log.txt")

def extract_images(pdf, outdir):
    outdir.mkdir(exist_ok=True, parents=True)
    run_cmd(f'pdfimages -all "{pdf}" "{outdir}/img"', outdir / "image_log.txt")

def ocr_pdf(pdf, outdir, lang='heb+eng'):
    outdir.mkdir(exist_ok=True, parents=True)
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    sidecar_txt = outdir / "ocr_output.txt"
    sidecar_hocr = outdir / "ocr_output.hocr"
    output_pdf = outdir / "ocr_output.pdf"

    cmd = (
        f'ocrmypdf --force-ocr --output-type pdf --rotate-pages --deskew '
        f'-l {lang} --sidecar "{sidecar_txt}" --pdf-renderer hocr '
        f'"{pdf}" "{output_pdf}"'
    )
    print(f"🔧 Running OCR on: {pdf}")
    result = subprocess.run(cmd, shell=True)

    if result.returncode != 0:
        print("❌ OCR failed.")
        return

    if not sidecar_txt.exists():
        print("⚠️ Sidecar text not found.")
    else:
        print("✅ OCR Text output created.")

def update_csv_row(pdf_path):
    pdf_name = pdf_path.name
    mod_time = datetime.fromtimestamp(pdf_path.stat().st_mtime).isoformat()
    with open(CSV_FILE, "a", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([pdf_name, mod_time, str(pdf_path.resolve())])

def process_file(pdf):
    print(f"🔍 Processing: {pdf}")
    base = OUTPUT_DIR / f"{pdf.stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    base.mkdir(parents=True, exist_ok=True)

    # תתי תיקובות
    meta_dir = base / "metadata"
    text_dir = base / "text"
    image_dir = base / "images"
    ocr_dir = OCR_DIR / pdf.stem
    meta_dir.mkdir(parents=True, exist_ok=True)
    text_dir.mkdir(parents=True, exist_ok=True)
    image_dir.mkdir(parents=True, exist_ok=True)

    extract_metadata(pdf, meta_dir)
    extract_text(pdf, text_dir)
    extract_images(pdf, image_dir)
    ocr_pdf(pdf, ocr_dir)
    update_csv_row(pdf)

    print(f"✅ Done: {pdf}\n")

def main():
    print(BANNER)
    parser = argparse.ArgumentParser(description="PDF Forensic Analysis CLI")
    parser.add_argument("target", help="PDF file or folder")
    args = parser.parse_args()

    target = Path(args.target)
    if target.is_file() and target.suffix.lower() == ".pdf":
        process_file(target)
    elif target.is_dir():
        for pdf in target.glob("*.pdf"):
            process_file(pdf)
    else:
        print("❌ Invalid input. Please specify a .pdf file or folder containing PDFs.")

if __name__ == "__main__":
    OUTPUT_DIR.mkdir(exist_ok=True)
    OCR_DIR.mkdir(exist_ok=True)
    with open(CSV_FILE, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["File Name", "Last Modified", "Full Path"])
    main()
