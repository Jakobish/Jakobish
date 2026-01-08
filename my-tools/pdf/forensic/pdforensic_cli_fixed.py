#!/usr/bin/env python3
#############################################
# Script: pdforensic_cli_fixed.py
# Purpose:
#   An interactive command-line tool for forensic analysis of PDF files.
#   Features:
#     - Accepts a single PDF or a folder of PDFs as input
#     - Supports selective or full execution of analysis steps:
#         - Metadata (-m)
#         - Text (-t)
#         - Structure (-s)
#         - Hidden content (-h)
#         - Images (-i)
#         - Hex dump (-x)
#         - OCR (-o)
#         - Stream decoding (-d)
#     - Uses common CLI tools: pdfinfo, exiftool, pdftotext, qpdf, mutool, grep, strings, xxd, pdfimages, ocrmypdf
#     - Generates organized output folders with extracted artifacts
# Output:
#   - Saved under: forensic_results/<pdf_name>_<timestamp>/
#   - Includes raw tool output, organized assets, and logs
#############################################

import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime
import shutil

ACTIONS = {
    "-m": "Metadata extraction (pdfinfo, exiftool)",
    "-t": "Text extraction (pdftotext)",
    "-s": "Structure analysis (qpdf, mutool)",
    "-h": "Hidden text search (strings, grep)",
    "-i": "Image extraction (pdfimages)",
    "-x": "Hex dump (xxd)",
    "-o": "OCR (ocrmypdf)",
    "-d": "Decode streams (qpdf --qdf)",
    "--all": "Run all analyses"
}

REQUIRED_TOOLS = [
    "pdfinfo", "exiftool", "pdftotext", "qpdf", "mutool",
    "strings", "grep", "xxd", "pdfimages", "ocrmypdf"
]

def check_tools():
    for tool in REQUIRED_TOOLS:
        if not shutil.which(tool):
            print(f"⚠️ WARNING: {tool} not found in PATH. Please install it!")

def run_cmd(command, output_path=None):
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        if output_path:
            with open(output_path, 'w', encoding='utf-8') as f:
                f.write(result.stdout + result.stderr)
        return result.stdout + result.stderr
    except Exception as e:
        return f"❌ Error running command: {command}\n{e}"

def perform_analysis(pdf_path, actions):
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    base_name = pdf_path.stem
    output_dir = Path(f"forensic_results/{base_name}_{timestamp}")
    asset_dir = output_dir / "assets"
    os.makedirs(asset_dir, exist_ok=True)

    shutil.copy(pdf_path, output_dir / "original.pdf")

    print(f"🔍 Processing: {pdf_path.name} → {output_dir}")

    if "-m" in actions or "--all" in actions:
        run_cmd(f"pdfinfo \"{pdf_path}\"", asset_dir / "pdf_info.txt")
        run_cmd(f"exiftool \"{pdf_path}\"", asset_dir / "exif_metadata.txt")

    if "-t" in actions or "--all" in actions:
        run_cmd(f"pdftotext \"{pdf_path}\" \"{asset_dir}/extracted_text.txt\"")

    if "-s" in actions or "--all" in actions:
        run_cmd(f"qpdf --json \"{pdf_path}\"", asset_dir / "qpdf_structure.json")
        run_cmd(f"qpdf --show-objects \"{pdf_path}\"", asset_dir / "qpdf_objects.txt")
        run_cmd(f"mutool info \"{pdf_path}\"", asset_dir / "mutool_info.txt")
        run_cmd(f"mutool extract \"{pdf_path}\" \"{asset_dir}/mutool_objects\"")

    if "-h" in actions or "--all" in actions:
        run_cmd(f"strings \"{pdf_path}\"", asset_dir / "strings_dump.txt")
        run_cmd(f"grep -i hidden \"{asset_dir}/strings_dump.txt\"", asset_dir / "hidden_text.txt")
        run_cmd(f"grep -i OC \"{asset_dir}/strings_dump.txt\" >> \"{asset_dir}/hidden_text.txt\"")

    if "-i" in actions or "--all" in actions:
        run_cmd(f"pdfimages -all \"{pdf_path}\" \"{asset_dir}/image\"")

    if "-x" in actions or "--all" in actions:
        run_cmd(f"xxd \"{pdf_path}\"", asset_dir / "pdf_hex_dump.txt")

    if "-o" in actions or "--all" in actions:
        run_cmd(f"ocrmypdf \"{pdf_path}\" \"{asset_dir}/ocr_output.pdf\"")

    if "-d" in actions or "--all" in actions:
        run_cmd(f"qpdf --qdf --object-streams=disable \"{pdf_path}\" \"{asset_dir}/decoded_output.pdf\"")

    print(f"✅ Finished: {pdf_path.name} → {output_dir}")

def interactive_menu():
    print("Select operations to perform (e.g., -m -t -h) or '--all':")
    for key, desc in ACTIONS.items():
        print(f"  {key:<8} {desc}")
    selection = input("Your choice: ").strip().split()
    return selection

def main():
    check_tools()

    if len(sys.argv) < 2:
        print("Usage: python3 pdforensic.py <file-or-folder> [options]")
        print("No file or folder provided. Exiting.")
        sys.exit(1)

    target_path = Path(sys.argv[1])
    selected_actions = sys.argv[2:] if len(sys.argv) > 2 else interactive_menu()

    pdf_files = []
    if target_path.is_file() and target_path.suffix.lower() == ".pdf":
        pdf_files = [target_path]
    elif target_path.is_dir():
        pdf_files = list(target_path.glob("*.pdf"))
    else:
        print("❌ Invalid input. Must be a PDF file or a folder containing PDFs.")
        sys.exit(1)

    for pdf in pdf_files:
        perform_analysis(pdf, selected_actions)

if __name__ == "__main__":
    main()
