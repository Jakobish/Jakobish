#!/usr/bin/env python3
#############################################
# Script: pdforensic.py
# Purpose:
#   A minimal forensic scanner for a single PDF file.
#   It:
#     - Accepts one PDF file as argument
#     - Creates an output folder: forensic_out_<filename>/
#     - Extracts:
#         - Metadata using exiftool
#         - Structural validation using qpdf --check
#         - Full text using pdftotext
#         - Metadata and document info using pdfinfo
#   Output:
#     - All results saved under: forensic_out_<filename>/
#############################################

import subprocess
import sys
import os
from pathlib import Path

def run_command(cmd, output_file=None):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if output_file:
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(result.stdout)
        else:
            print(result.stdout)
    except Exception as e:
        print(f"❌ Error running command: {cmd}\n{e}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 pdforensic.py <file.pdf>")
        sys.exit(1)

    pdf_path = Path(sys.argv[1])
    if not pdf_path.exists() or pdf_path.suffix.lower() != '.pdf':
        print("❌ Invalid PDF file.")
        sys.exit(1)

    output_dir = Path(f"forensic_out_{pdf_path.stem}")
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"[✓] Analyzing: {pdf_path.name}")
    print(f"[→] Output dir: {output_dir}")

    # Step 1: Metadata
    run_command(f'exiftool -a -G1 -s "{pdf_path}"', output_dir / "metadata.txt")

    # Step 2: QPDF structural check
    run_command(f'qpdf --check "{pdf_path}"', output_dir / "qpdf_check.txt")

    # Step 3: Text extraction
    run_command(f'pdftotext "{pdf_path}" "{output_dir}/text.txt"')

    # Step 4: PDF Info (structure)
    run_command(f'pdfinfo "{pdf_path}"', output_dir / "pdfinfo.txt")

    print("\n✅ Done. Check output in:", output_dir)

if __name__ == "__main__":
    main()
