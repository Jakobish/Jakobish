#!/usr/bin/env python3
#############################################
# Script: pdforensic_full.py
# Purpose:
#   This Python script performs a comprehensive forensic analysis of a single PDF file.
#   It:
#     - Checks for required command-line tools
#     - Creates a timestamped output directory for organized results
#     - Extracts metadata using pdfinfo and exiftool
#     - Extracts visible and hidden text using pdftotext and grep
#     - Analyzes internal PDF structure using qpdf and mutool
#     - Extracts embedded images using pdfimages
#     - Dumps raw binary content with xxd
#     - Gathers all outputs into a Markdown report
# Output:
#   - All results are saved in: forensic_results/<pdf_name>_<timestamp>
#   - Markdown report summarizing the analysis is included
#############################################
import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime

REQUIRED_TOOLS = [
    "pdfinfo", "exiftool", "pdftotext", "qpdf", "mutool",
    "strings", "grep", "xxd", "pdfimages"
]

def check_tools():
    missing = []
    for tool in REQUIRED_TOOLS:
        if not shutil.which(tool):
            print(f"⚠️ WARNING: {tool} not found. Please install it!")
            missing.append(tool)
    if missing:
        print("\nSome tools are missing. The script may not run properly.")
        print("Missing tools:", ", ".join(missing))

def run_cmd(command, output_path=None):
    try:
        result = subprocess.run(command, shell=True, text=True, capture_output=True)
        if output_path:
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(result.stdout + result.stderr)
        return result.stdout + result.stderr
    except Exception as e:
        return f"❌ Error running {command}: {e}"

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 pdforensic.py <file.pdf>")
        sys.exit(1)

    input_file = Path(sys.argv[1])
    if not input_file.exists() or input_file.suffix.lower() != ".pdf":
        print("❌ Error: Invalid PDF file.")
        sys.exit(1)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    base_name = input_file.stem
    output_dir = Path(f"forensic_results/{base_name}_{timestamp}")
    asset_dir = output_dir / "assets"
    os.makedirs(asset_dir, exist_ok=True)

    print(f"🔍 Processing: {input_file.name} → Saving to {output_dir}")
    # Copy original
    original_copy = output_dir / "original.pdf"
    original_copy.write_bytes(input_file.read_bytes())

    # Run all tools
    run_cmd(f'pdfinfo "{input_file}"', asset_dir / "pdf_info.txt")
    run_cmd(f'exiftool "{input_file}"', asset_dir / "exif_metadata.txt")
    run_cmd(f'pdftotext "{input_file}" "{asset_dir}/extracted_text.txt"')
    run_cmd(f'qpdf --json "{input_file}"', asset_dir / "qpdf_structure.json")
    run_cmd(f'qpdf --show-objects "{input_file}"', asset_dir / "qpdf_objects.txt")
    run_cmd(f'mutool info "{input_file}"', asset_dir / "mutool_info.txt")
    run_cmd(f'mutool extract "{input_file}" "{asset_dir}/mutool_objects"')
    run_cmd(f'strings "{input_file}"', asset_dir / "strings_dump.txt")
    run_cmd(f'grep -i hidden "{asset_dir}/strings_dump.txt"', asset_dir / "hidden_text.txt")
    run_cmd(f'grep -i OC "{asset_dir}/strings_dump.txt" >> "{asset_dir}/hidden_text.txt"')
    run_cmd(f'xxd "{input_file}"', asset_dir / "pdf_hex_dump.txt")
    run_cmd(f'pdfimages -all "{input_file}" "{asset_dir}/image"')

    # Generate Markdown summary
    md_file = output_dir / f"{base_name}_report_{timestamp}.md"
    with open(md_file, "w", encoding="utf-8") as f:
        f.write(f"# Forensic Analysis Report for {base_name}\n")
        f.write(f"Generated on {datetime.now().isoformat()}\n\n")

        def write_section(title, path):
            f.write(f"## {title}\n")
            if Path(path).exists():
                content = Path(path).read_text(encoding="utf-8", errors="ignore")
                f.write(content + "\n\n")
            else:
                f.write("No data found.\n\n")

        write_section("Metadata", asset_dir / "pdf_info.txt")
        write_section("Extracted Text", asset_dir / "extracted_text.txt")
        write_section("Hidden Text", asset_dir / "hidden_text.txt")
        write_section("QPDF Object Dump", asset_dir / "qpdf_objects.txt")
        write_section("HEX Dump", asset_dir / "pdf_hex_dump.txt")

    print(f"✅ Done! Report saved in {output_dir}")

if __name__ == "__main__":
    import shutil
    check_tools()
    main()
