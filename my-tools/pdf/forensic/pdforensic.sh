#!/bin/bash
#############################################
# Script: pdforensic.sh
# Purpose:
#   A powerful Bash script for automated forensic analysis of all PDF files in the current directory.
#   Features:
#     - Iterates over all top-level PDF files (ignores subdirectories)
#     - Creates a timestamped folder for each processed PDF under forensic_results/
#     - Performs:
#         - Basic metadata extraction (pdfinfo, exiftool)
#         - Visible and hidden text extraction (pdftotext, strings, grep)
#         - PDF structure and object inspection (qpdf with JSON + object dump)
#         - Hidden objects and font data (mutool info, mutool extract)
#         - Full hex dump for binary inspection (xxd)
#         - Image extraction (pdfimages)
#     - Generates:
#         - Individual Markdown reports per file summarizing key findings
#         - Optionally, a master summary Markdown for all reports
# Output:
#   - forensic_results/<pdfname>_<timestamp>/ containing:
#       - original.pdf
#       - assets/ (all extracted data)
#       - markdown report for each file
#   - Total runtime summary printed at end
#1

# 🛠️ תיקיית הפלט הראשית
PDF_DIR=$(dirname "$file")
OUTPUT_DIR="${PDF_DIR}/forensic_results"
mkdir -p "$OUTPUT_DIR"

# 📌 רשימת הכלים הדרושים
REQUIRED_TOOLS=("pdfinfo" "exiftool" "pdftotext" "qpdf" "mutool" "strings" "grep" "pdfimages")

# 🔍 בדיקת כלים מותקנים
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "⚠️ WARNING: $tool not found. Please install it!"
    fi
done

# 🕒 שמירת זמן התחלה
start_time=$(date +%s)

if [ -z "$1" ]; then
    echo "❌ No input PDF provided. Drag-and-drop a PDF file or run via Automator."
    exit 1
fi

file="$1"
filename=$(basename "$file" .pdf)
filedir="$OUTPUT_DIR/$filename"
asset_dir="$filedir/assets"
mkdir -p "$asset_dir"

echo "🔍 Processing: $file -> Saving to $filedir"

    # Original PDF copying removed as per requirements

    # 🔹 חילוץ metadata בסיסי
    echo "📄 Extracting metadata..."
    pdfinfo "$file" > "$asset_dir/pdf_info.txt" 2>&1
    exiftool "$file" > "$asset_dir/exif_metadata.txt" 2>&1

    # 📜 חילוץ טקסט גלוי ונסתר
    echo "📄 Extracting text..."
    pdftotext "$file" "$asset_dir/extracted_text.txt" 2>&1

    # 🔎 ניתוח מבנה ה-PDF עם QPDF
    echo "🔎 Running QPDF analysis..."
    qpdf --json "$file" > "$asset_dir/qpdf_structure.json" 2>"$asset_dir/qpdf_errors.txt"
    qpdf --show-objects "$file" > "$asset_dir/qpdf_objects.txt" 2>&1

    # 🖼️ חילוץ שכבות, גופנים ואובייקטים נסתרים
    echo "🖼️ Extracting hidden layers and objects..."
    mutool info "$file" > "$asset_dir/mutool_info.txt" 2>&1
    mutool extract "$file" "$asset_dir/mutool_objects" 2>&1

    # 🔍 מציאת טקסט מוסתר וחקירת שכבות
    echo "🔎 Searching for hidden text..."
    strings "$file" > "$asset_dir/strings_dump.txt" 2>&1
    grep -i "hidden" "$asset_dir/strings_dump.txt" > "$asset_dir/hidden_text.txt" 2>&1
    grep -i "OC" "$asset_dir/strings_dump.txt" >> "$asset_dir/hidden_text.txt" 2>&1

    # 📸 חילוץ כל התמונות מה-PDF
    echo "📸 Extracting images..."
    pdfimages -all "$file" "$asset_dir/image" 2>&1

    # 📝 יצירת Markdown מסכם לכל קובץ בנפרד (ללא HEX & בינאריים)
    MD_FILE="$filedir/${filename}_report.md"
    {
        echo "# Forensic Analysis Report for $filename"
        echo "Generated on $(date)"
        echo ""
        echo "## Metadata"
        cat "$asset_dir/pdf_info.txt" 2>/dev/null || echo "No metadata found."
        echo ""
        echo "## Extracted Text"
        cat "$asset_dir/extracted_text.txt" 2>/dev/null || echo "No text extracted."
        echo ""
        echo "## Hidden Text Analysis"
        cat "$asset_dir/hidden_text.txt" 2>/dev/null || echo "No hidden text detected."
        echo ""
        echo "## QPDF Object Dump (filtered)"
        grep -E "obj|stream|endobj" "$asset_dir/qpdf_objects.txt" 2>/dev/null || echo "No object data extracted."
        echo ""
    } > "$MD_FILE"

    echo "✅ Finished processing: $file -> Results saved in $filedir"
done
h
# 🕒 חישוב זמן ריצה
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

echo "🏁 Processing completed in $elapsed_time 
seconds!"
echo "📂 All results are saved in: $OUTPUT_DIR"#!/bin/bash
#1
# 🛠️ תיקיית הפלט הראשית
OUTPUT_DIR="forensic_results"
mkdir -p "$OUTPUT_DIR"

# 📌 רשימת הכלים הדרושים
REQUIRED_TOOLS=("pdfinfo" "exiftool" "pdftotext" "qpdf" "mutool" "strings" "grep" "xxd" "pdfimages")

# 🔍 בדיקת כלים מותקנים
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "⚠️ WARNING: $tool not found. Please install it!"
    fi
done

# 🕒 שמירת זמן התחלה
start_time=$(date +%s)

# 🎯 מעבר על כל קובצי ה-PDF בתיקייה הנוכחית (ולא בתיקיות המשנה)
find . -maxdepth 1 -type f -iname "*.pdf" | while read -r file; do
    filename=$(basename "$file" .pdf)
    timestamp=$(date +"%Y%m%d_%H%M%S")  # הוספת timestamp למניעת דריסת קבצים קודמים
    filedir="$OUTPUT_DIR/${filename}_${timestamp}"
    
    # ✅ בדיקה אם כבר עיבדנו את הקובץ הזה, אם כן - מדלגים
    if [ -d "$filedir" ]; then
        echo "🚀 Skipping: $file (Already processed)"
        continue
    fi

    mkdir -p "$filedir"
    asset_dir="$filedir/assets"
    mkdir -p "$asset_dir"

    echo "🔍 Processing: $file -> Saving to $filedir"

    # 📝 העתקת הקובץ המקורי לשמירת מקור
    cp "$file" "$filedir/original.pdf"

    # 🔹 חילוץ metadata בסיסי
    echo "📄 Extracting metadata..."
    pdfinfo "$file" > "$asset_dir/pdf_info.txt" 2>&1
    exiftool "$file" > "$asset_dir/exif_metadata.txt" 2>&1

    # 📜 חילוץ טקסט גלוי ונסתר
    echo "📄 Extracting text..."
    pdftotext "$file" "$asset_dir/extracted_text.txt" 2>&1

    # 🔎 ניתוח מבנה ה-PDF עם QPDF
    echo "🔎 Running QPDF analysis..."
    qpdf --json "$file" > "$asset_dir/qpdf_structure.json" 2>"$asset_dir/qpdf_errors.txt"
    qpdf --show-objects "$file" > "$asset_dir/qpdf_objects.txt" 2>&1

    # 🖼️ חילוץ שכבות, גופנים ואובייקטים נסתרים
    echo "🖼️ Extracting hidden layers and objects..."
    mutool info "$file" > "$asset_dir/mutool_info.txt" 2>&1
    mutool extract "$file" "$asset_dir/mutool_objects" 2>&1

    # 🔍 מציאת טקסט מוסתר וחקירת שכבות
    echo "🔎 Searching for hidden text..."
    strings "$file" > "$asset_dir/strings_dump.txt" 2>&1
    grep -i "hidden" "$asset_dir/strings_dump.txt" > "$asset_dir/hidden_text.txt" 2>&1
    grep -i "OC" "$asset_dir/strings_dump.txt" >> "$asset_dir/hidden_text.txt" 2>&1

    # 🛠️ המרת הקובץ להקס (לזיהוי שינויים)
    echo "🔬 Performing HEX dump..."
    xxd "$file" > "$asset_dir/pdf_hex_dump.txt" 2>&1

    # 📸 חילוץ כל התמונות מה-PDF
    echo "📸 Extracting images..."
    pdfimages -all "$file" "$asset_dir/image" 2>&1

    # 📝 יצירת Markdown מסכם לכל קובץ בנפרד
    MD_FILE="$filedir/${filename}_report_${timestamp}.md"
    echo "# Forensic Analysis Report for $filename" > "$MD_FILE"
    echo "Generated on $(date)" >> "$MD_FILE"
    echo "" >> "$MD_FILE"
    echo "## Metadata" >> "$MD_FILE"
    cat "$asset_dir/pdf_info.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"
    echo "## Extracted Text" >> "$MD_FILE"
    cat "$asset_dir/extracted_text.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"
    echo "## Hidden Text Analysis" >> "$MD_FILE"
    cat "$asset_dir/hidden_text.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"
    echo "## QPDF Object Dump" >> "$MD_FILE"
    cat "$asset_dir/qpdf_objects.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"
    echo "## HEX Dump" >> "$MD_FILE"
    cat "$asset_dir/pdf_hex_dump.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"

    echo "✅ Finished processing: $file -> Results saved in $filedir"
done

# 🕒 חישוב זמן ריצה
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

echo "🏁 Processing completed in $elapsed_time seconds!"
echo "📂 All results are saved in: $OUTPUT_DIR"#!/bin/bash

# 🛠️ תיקיית הפלט הראשית
OUTPUT_DIR="forensic_results"
mkdir -p "$OUTPUT_DIR"

# 📌 רשימת הכלים הדרושים
REQUIRED_TOOLS=("pdfinfo" "exiftool" "pdftotext" "qpdf" "mutool" "strings" "grep" "xxd" "pdfimages")

# 🔍 בדיקת כלים מותקנים
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v $tool &> /dev/null; then
        echo "⚠️ WARNING: $tool not found. Please install it!"
    fi
done

# 🕒 שמירת זמן התחלה
start_time=$(date +%s)

# 🎯 מעבר על כל קובצי ה-PDF בתיקייה הנוכחית
find . -maxdepth 1 -type f -iname "*.pdf" | while read -r file; do
    filename=$(basename "$file" .pdf)
    timestamp=$(date +"%Y%m%d_%H%M%S")  # הוספת timestamp למניעת דריסת קבצים קודמים
    filedir="$OUTPUT_DIR/${filename}_${timestamp}"
    mkdir -p "$filedir"
    asset_dir="$filedir/assets"
    mkdir -p "$asset_dir"

    echo "🔍 Processing: $file -> Saving to $filedir"

    # 📝 העתקת הקובץ המקורי לשמירת מקור
    cp "$file" "$filedir/original.pdf"

    # 🔹 חילוץ metadata בסיסי
    echo "📄 Extracting metadata..."
    pdfinfo "$file" > "$asset_dir/pdf_info.txt" 2>&1
    exiftool "$file" > "$asset_dir/exif_metadata.txt" 2>&1

    # 📜 חילוץ טקסט גלוי ונסתר
    echo "📄 Extracting text..."
    pdftotext "$file" "$asset_dir/extracted_text.txt" 2>&1

    # 🔎 ניתוח מבנה ה-PDF עם QPDF
    echo "🔎 Running QPDF analysis..."
    qpdf --json "$file" > "$asset_dir/qpdf_structure.json" 2>"$asset_dir/qpdf_errors.txt"
    qpdf --show-objects "$file" > "$asset_dir/qpdf_objects.txt" 2>&1

    # 🖼️ חילוץ שכבות, גופנים ואובייקטים נסתרים
    echo "🖼️ Extracting hidden layers and objects..."
    mutool info "$file" > "$asset_dir/mutool_info.txt" 2>&1
    mutool extract "$file" "$asset_dir/mutool_objects" 2>&1

    # 🔍 מציאת טקסט מוסתר וחקירת שכבות
    echo "🔎 Searching for hidden text..."
    strings "$file" > "$asset_dir/strings_dump.txt" 2>&1
    grep -i "hidden" "$asset_dir/strings_dump.txt" > "$asset_dir/hidden_text.txt" 2>&1
    grep -i "OC" "$asset_dir/strings_dump.txt" >> "$asset_dir/hidden_text.txt" 2>&1

    # 🛠️ המרת הקובץ להקס (לזיהוי שינויים)
    echo "🔬 Performing HEX dump..."
    xxd "$file" > "$asset_dir/pdf_hex_dump.txt" 2>&1

    # 📸 חילוץ כל התמונות מה-PDF
    echo "📸 Extracting images..."
    pdfimages -all "$file" "$asset_dir/image" 2>&1

    # 📝 יצירת Markdown מסכם לכל קובץ בנפרד
    MD_FILE="$filedir/${filename}_report_${timestamp}.md"
    echo "# Forensic Analysis Report for $filename" > "$MD_FILE"
    echo "Generated on $(date)" >> "$MD_FILE"
    echo "" >> "$MD_FILE"
    echo "## Metadata" >> "$MD_FILE"
    cat "$asset_dir/pdf_info.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"
    echo "## Extracted Text" >> "$MD_FILE"
    cat "$asset_dir/extracted_text.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"
    echo "## Hidden Text Analysis" >> "$MD_FILE"
    cat "$asset_dir/hidden_text.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"
    echo "## QPDF Object Dump" >> "$MD_FILE"
    cat "$asset_dir/qpdf_objects.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"
    echo "## HEX Dump" >> "$MD_FILE"
    cat "$asset_dir/pdf_hex_dump.txt" >> "$MD_FILE" 2>/dev/null
    echo "" >> "$MD_FILE"

    echo "✅ Finished processing: $file -> Results saved in $filedir"
done

# 🕒 חישוב זמן ריצה
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

echo "🏁 Processing completed in $elapsed_time seconds!"
echo "📂 All results are saved in: $OUTPUT_DIR"# 🛠️ תיקיית הפלט הראשית

