# 🧭 Workflow לעיבוד קובצי PDF משפטיים

תהליך עבודה קבוע לעיבוד, סינון, וחילוץ תובנות מקבצי PDF בתיק המשפטי.

---

## 🔁 שלב 1: מיון לפי תוכנה יוצרת (Producer)

```bash
exiftool -overwrite_original '-Directory<${Producer;s/[^A-Za-z0-9]+/_/g}' pdfs/to_review/*.pdf
```

* יוצרת תיקיות לפי שם התוכנה שיצרה את הקובץ (Acrobat, AWS, PDFCreator וכו’)
* מאפשרת:
  * 🧹 סינון ראשוני לפי מקורות לא רלוונטיים (למשל AWS, בזק)
  * ✅ זיהוי קבצים אמינים (Acrobat Pro)
  * 🛑 זריקת קבצים בעייתיים (PDFCreator, לא מזוהים)

---

## 🗑 שלב 2: ניקוי קבצים לפי רשימת פסילה (BlackList)

```bash
mv pdfs/to_review/AWS_*pdfs/_trash/
mv pdfs/to_review/Bezeq_* pdfs/_trash/
```

* קבצים שאינם נדרשים מועברים ל־_trash
* מה שלא מוכר – נבדק ידנית → ואז נזרק או נשמר

---

## 🧠 שלב 3: OCR (אם נדרש)

למקרים בהם הקובץ הוא תמונה או נסרק (ללא טקסט אמיתי):

```bash
ocrmypdf input.pdf output.pdf
```

* הפלט נשמר לקובץ חדש או מוחלף (--force-ocr)
* שימוש ב־Docker או Homebrew (תלוי בהתקנה)

---

## 📄 שלב 4: חילוץ דף ראשון (כדי למיין לפי תוכן)

באמצעות pdfplumber:

```python
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

* בודק מילות מפתח חשובות (ramimor, discount, partner)
* ממיין לתיקיות לפי תוכן הקובץ (ע”פ מילים שהוגדרו מראש)

---

## 🧠 שלב 5: שינוי שם / תיוג / תיעוד עם AI

* על בסיס הטקסט שחולץ:
  * שיכתוב כותרת לקובץ
  * תיעוד / תקציר
  * שינוי שם לקובץ → לדוגמה:

```
2023-04-15_invoice_discount_ramimor.pdf
```

---

## 🔄 שלב 6: עדכון תאריכי קובץ לפי מטא־דאטה

```bash
exiftool -overwrite_original \
  "-FileCreateDate<CreationDate" \
  "-FileModifyDate<CreationDate" \
  *.pdf
```

* שמירה על תאריכים אותנטיים – לצורך מעקב פורנזי

---

### 📦 הצעה

רוצה שאכין את זה כקובץ `workflow.md` בתוך `docs/`
או לשמור כ־README בתיקיית `scripts/` שלך?
