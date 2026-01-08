#!/usr/bin/env python3
#############################################
# Script: pdforensic_cli_ultimate.py
# Purpose:
#   This is the ultimate interactive CLI tool for advanced PDF forensic analysis.
#   It allows selective or full execution of multiple analysis steps using:
#     - Metadata extraction (pdfinfo, exiftool)
#     - Text extraction (pdftotext)
#     - Structure analysis (qpdf, mutool)
#     - Hidden text and layer detection (strings, grep)
#     - Image extraction (pdfimages)
#     - Binary hex dump (xxd)
#     - OCR reconstruction (ocrmypdf)
#     - Stream decoding (qpdf --qdf)
#   Users can provide a PDF or folder of PDFs as input, choose actions via command-line
#   flags or an interactive menu, and results are saved per file in timestamped folders.
# Output:
#   - Results are saved to: forensic_results/<filename>_<timestamp>
#   - Each analysis produces artifacts like text, images, JSON, logs, and PDF outputs
#############################################

import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime
import shutil

def print_banner():
    print(r"""
██████╗ ███████╗██████╗ ███████╗ ██████╗ ██████╗ ███████╗███╗   ██╗██╗ ██████╗
██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝ ██╔══██╗██╔════╝████╗  ██║██║██╔════╝
██║  ██║█████╗  ██████╔╝█████╗  ██║  ███╗██████╔╝█████╗  ██╔██╗ ██║██║██║     
██║  ██║██╔══╝  ██╔══██╗██╔══╝  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║██║     
██████╔╝███████╗██║  ██║███████╗╚██████╔╝██║     ███████╗██║ ╚████║██║╚██████╗
╚═════╝ ╚══════╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝╚═╝ ╚═════╝
            Forensic CLI Tool for PDF Analysis ✨
""")

ACTIONS = {
    "m": "Metadata extraction (pdfinfo, exiftool)",
    "t": "Text extraction (pdftotext)",
    "s": "Structure analysis (qpdf, mutool)",
    "h": "Hidden text search (strings, grep)",
    "i": "Image extraction (pdfimages)",
    "x": "Hex dump (xxd)",
    "o": "OCR (ocrmypdf)",
    "d": "Decode streams (qpdf --qdf)",
    "a": "Run all analyses"
}

REQUIRED_TOOLS = [
    "pdfinfo", "exiftool", "pdftotext", "qpdf", "mutool",
    "strings", "grep", "xxd", "pdfimages", "ocrmypdf"
]

def check_tools():
    for tool in REQUIRED_TOOLS:
        if not shutil.which(tool):
            print(f"⚠️  WARNING: {tool} not found in PATH. Please install it!")

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

    if "m" in actions or "a" in actions:
        run_cmd(f"pdfinfo \"{pdf_path}\"", asset_dir / "pdf_info.txt")
        run_cmd(f"exiftool \"{pdf_path}\"", asset_dir / "exif_metadata.txt")

    if "t" in actions or "a" in actions:
        run_cmd(f"pdftotext \"{pdf_path}\" \"{asset_dir}/extracted_text.txt\"")

    if "s" in actions or "a" in actions:
        run_cmd(f"qpdf --json \"{pdf_path}\"", asset_dir / "qpdf_structure.json")
        run_cmd(f"qpdf --show-objects \"{pdf_path}\"", asset_dir / "qpdf_objects.txt")
        run_cmd(f"mutool info \"{pdf_path}\"", asset_dir / "mutool_info.txt")
        run_cmd(f"mutool extract \"{pdf_path}\" \"{asset_dir}/mutool_objects\"")

    if "h" in actions or "a" in actions:
        run_cmd(f"strings \"{pdf_path}\"", asset_dir / "strings_dump.txt")
        run_cmd(f"grep -i hidden \"{asset_dir}/strings_dump.txt\"", asset_dir / "hidden_text.txt")
        run_cmd(f"grep -i OC \"{asset_dir}/strings_dump.txt\" >> \"{asset_dir}/hidden_text.txt\"")

    if "i" in actions or "a" in actions:
        run_cmd(f"pdfimages -all \"{pdf_path}\" \"{asset_dir}/image\"")

    if "x" in actions or "a" in actions:
        run_cmd(f"xxd \"{pdf_path}\"", asset_dir / "pdf_hex_dump.txt")

    if "o" in actions or "a" in actions:
        run_cmd(f"ocrmypdf \"{pdf_path}\" \"{asset_dir}/ocr_output.pdf\"")

    if "d" in actions or "a" in actions:
        run_cmd(f"qpdf --qdf --object-streams=disable \"{pdf_path}\" \"{asset_dir}/decoded_output.pdf\"")

    print(f"✅ Finished: {pdf_path.name} → {output_dir}")

def interactive_menu():
    print_banner()
    print("Available operations:")
    for key, desc in ACTIONS.items():
        print(f"  {key}     {desc}")
    raw = input("\nSelect operations (e.g., mtx or m,t,x or 'a' for all): ").lower()
    return parse_action_args(raw.split(",")) if "," in raw else list(raw)

def parse_action_args(args):
    clean = []
    for item in args:
        for char in item:
            if char in ACTIONS and char not in clean:
                clean.append(char)
    return clean

def usage():
    print_banner()
    print("Usage: pdforensic.py <file|folder> [options]\n")
    print("Options:")
    for k, v in ACTIONS.items():
        print(f"  -{k:<3} {v}")
    print("\nExamples:")
    print("  pdforensic.py file.pdf -m -t -o")
    print("  pdforensic.py folder/ a")
    print("  pdforensic.py file.pdf --all\n")

def main():
    check_tools()

    if len(sys.argv) < 2:
        usage()
        return

    target_path = Path(sys.argv[1])
    raw_args = sys.argv[2:]

    selected_actions = []
    if not raw_args:
        selected_actions = interactive_menu()
    else:
        for arg in raw_args:
            arg = arg.lstrip("-").lower()
            selected_actions.extend(list(arg))

        selected_actions = list({a for a in selected_actions if a in ACTIONS})

        if not selected_actions:
            print("❌ Invalid or no valid options selected.")
            usage()
            return

    if target_path.is_file() and target_path.suffix.lower() == ".pdf":
        pdf_files = [target_path]
    elif target_path.is_dir():
        pdf_files = list(target_path.glob("*.pdf"))
    else:
        print("❌ Invalid input. Must be a PDF file or folder.")
        return

    for pdf in pdf_files:
        perform_analysis(pdf, selected_actions)

    again = input("\n🔁 Do you want to analyze another file? [Y/n]: ").strip().lower()
    if again in ("", "y", "yes"):
        os.execl(sys.executable, sys.executable, *sys.argv)

if __name__ == "__main__":
    main()
