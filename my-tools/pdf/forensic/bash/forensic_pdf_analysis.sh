#############################################
# Script: forensic_pdf_analysis.sh
# Purpose:
#   This script performs forensic analysis on all PDF files in the current directory.
#   It:
#     - Verifies presence of required tools (pdfinfo, exiftool, pdftotext, qpdf, mutool, etc.)
#     - Creates a structured output directory with timestamped subfolders
#     - Extracts:
#         - Metadata using pdfinfo and exiftool
#         - Visible and hidden text using pdftotext, strings, grep
#         - Object structure using qpdf
#         - Images using pdfimages
#         - Embedded objects and fonts using mutool
#         - Binary HEX dump using xxd
#     - Generates a Markdown report per file
#     - Compiles a main summary report with links to detailed reports
# Output:
#   - All results saved under: forensic_results/
#   - One folder per PDF with extracted data and reports
#   - A top-level Markdown report summarizing the run
#############################################
#!/bin/bash
#1

# 🛠️ תיקיית הפלט הראשית
OUTPUT_DIR="forensic_results"
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

    # 📸 חילוץ כל התמונות מה-PDF
    echo "📸 Extracting images..."
    pdfimages -all "$file" "$asset_dir/image" 2>&1

    # 📝 יצירת Markdown מסכם לכל קובץ בנפרד (ללא HEX & בינאריים)
    MD_FILE="$filedir/${filename}_report_${timestamp}.md"
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

# 📂 קובץ Markdown ראשי לכל התהליך (כולל חותמת זמן)
RUN_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MAIN_MD_FILE="$OUTPUT_DIR/forensic_summary_${RUN_TIMESTAMP}.md"
echo "# Forensic PDF Analysis Report - Run $RUN_TIMESTAMP" > "$MAIN_MD_FILE"
echo "Generated on $(date)" >> "$MAIN_MD_FILE"
echo "" >> "$MAIN_MD_FILE"

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

    # 📝 יצירת Markdown מסכם לכל קובץ
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

    # 📜 עדכון הדוח המרכזי
    echo "## Report for $filename" >> "$MAIN_MD_FILE"
    echo "[View Detailed Report](./${filename}_${timestamp}/${filename}_report_${timestamp}.md)" >> "$MAIN_MD_FILE"
    echo "" >> "$MAIN_MD_FILE"

    echo "✅ Finished processing: $file -> Results saved in $filedir"
done

# 🕒 חישוב זמן ריצה
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

echo "🏁 Processing completed in $elapsed_time seconds!"
echo "📂 All results are saved in: $OUTPUT_DIR"bin/bash

# 🛠️ תיקיית הפלט הראשית
OUTPUT_DIR="forensic_results"
mkdir -p "$OUTPUT_DIR"

# 📌 רשימת הכלים הדרושים
REQUIRED_TOOLS=("pdfinfo" "exiftool" "pdftotext" "qpdf" "mutool" "strings" "grep" "xxd")

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

    echo "🔍 Processing: $file -> Saving to $filedir"

    # 📝 העתקת הקובץ המקורי לשמירת מקור
    cp "$file" "$filedir/original.pdf"

    # 🔹 חילוץ metadata בסיסי
    echo "📄 Extracting metadata..."
    pdfinfo "$file" > "$filedir/pdf_info.txt" 2>&1
    exiftool "$file" > "$filedir/exif_metadata.txt" 2>&1

    # 📜 חילוץ טקסט גלוי ונסתר
    echo "📄 Extracting text..."
    pdftotext "$file" "$filedir/extracted_text.txt" 2>&1

    # 🔎 ניתוח מבנה ה-PDF עם QPDF
    echo "🔎 Running QPDF analysis..."
    qpdf --json "$file" > "$filedir/qpdf_structure.json" 2>"$filedir/qpdf_errors.txt"
    qpdf --show-objects "$file" > "$filedir/qpdf_objects.txt" 2>&1

    # 🖼️ חילוץ שכבות, גופנים ואובייקטים נסתרים
    echo "🖼️ Extracting hidden layers and objects..."
    mutool info "$file" > "$filedir/mutool_info.txt" 2>&1
    mutool extract "$file" "$filedir/mutool_objects" 2>&1

    # 🔍 מציאת טקסט מוסתר וחקירת שכבות
    echo "🔎 Searching for hidden text..."
    strings "$file" > "$filedir/strings_dump.txt" 2>&1
    grep -i "hidden" "$filedir/strings_dump.txt" > "$filedir/hidden_text.txt" 2>&1
    grep -i "OC" "$filedir/strings_dump.txt" >> "$filedir/hidden_text.txt" 2>&1

    # 🛠️ המרת הקובץ להקס (לזיהוי שינויים)
    echo "🔬 Performing HEX dump..."
    xxd "$file" > "$filedir/pdf_hex_dump.txt" 2>&1

    echo "✅ Finished processing: $file -> Results saved in $filedir"
done

# 🕒 חישוב זמן ריצה
end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

echo "🏁 Processing completed in $elapsed_time seconds!"
echo "📂 All results are saved in: $OUTPUT_DIR"


