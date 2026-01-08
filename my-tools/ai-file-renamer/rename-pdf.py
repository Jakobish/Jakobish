from fileinput import filename
import os
import re
import ocrmypdf
import tempfile
from pypdf import PdfReader
import logging
import argparse
import requests
from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type
import subprocess

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')

def extract_text_from_first_page(pdf_path):
    """
    Extract text from the first page of a PDF file.
    Falls back to OCR using ocrmypdf if text extraction yields minimal content.
    """
    # First, try extracting text from the first page using pdftotext
    try:
        result = subprocess.run(
            ["pdftotext", "-f", "1", "-l", "1", "-enc", "UTF-8", pdf_path, "-"],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            text = result.stdout.strip()
            if len(text) >= 50:
                return text
    except subprocess.TimeoutExpired:
        logging.warning(f"pdftotext timed out for {pdf_path}")
    except FileNotFoundError:
        logging.error("pdftotext not found. Install poppler-utils (pdftotext).")
        return ""

    # Fallback to OCR with ocrmypdf API
    logging.info("Fallback to OCR using ocrmypdf.")
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_pdf = os.path.join(temp_dir, "ocr_output.pdf")
            # OCR the PDF using the Python API
            ocrmypdf.ocr(pdf_path, temp_pdf, language='heb+eng', redo_ocr=True)

            # Extract text from the OCR'd PDF
            text_result = subprocess.run(
                ["pdftotext", "-f", "1", "-l", "1", "-enc", "UTF-8", temp_pdf, "-"],
                capture_output=True, text=True, timeout=30
            )
            if text_result.returncode == 0:
                text = text_result.stdout.strip()
                return text
            else:
                logging.error(f"pdftotext failed after OCR: {text_result.stderr}")
    except ocrmypdf.exceptions.ExitCodeError as e:
        logging.error(f"ocrmypdf API failed: {e}")
    except subprocess.TimeoutExpired:
        logging.warning("pdftotext timed out after OCR")
    except FileNotFoundError:
        logging.error("pdftotext not found. Install poppler-utils (pdftotext).")

    return ""
def sanitize_filename(title):
    """
    Sanitize the title to make it a valid filename.
    """
    # Basic cleanup first
    title = title.strip()  # Remove leading/trailing whitespace
    if not title:
        return "untitled.pdf"
    # Replace invalid characters with underscores
    sanitized = re.sub(r'[<>:"/\\|?*\x00-\x1F]', '_', title)
    # Collapse multiple underscores and remove leading/trailing ones
    sanitized = re.sub(r'_+', '_', sanitized).strip('_')
    # Limit length
    return sanitized[:150] or "untitled.pdf"


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10), retry=retry_if_exception_type(requests.RequestException))
def generate_title_with_gemini(pdf_text, api_key, model='gemini-1.5-flash'):
    """
    Use the Gemini API to generate a file title based on the PDF text content.
    Updated to use an active model (flash for speed; switch to pro for long docs).
    """
    headers = {'Content-Type': 'application/json'}
    prompt = (
        "You are tasked to suggest a filename for a PDF document. The provided text is EXTRACTED FROM THE FIRST PAGE ONLY—it may be incomplete, OCR-generated (possibly with errors), or insufficient to fully represent the document. "
        "Your goal: Propose a concise, descriptive title as the filename in the document's ORIGINAL LANGUAGE. Make it filename-safe (no special characters, spaces allowed if simple). Keep under 80 characters. "
        "Respond ONLY with the filename text—NO explanations, NO prefixes/suffixes like 'Title:', NO markdown, NO additional text. Just the clean filename. "
        "Guidelines: "
        "- If text is gibberish, unclear, too brief (<20 characters), or insufficient to suggest a meaningful filename, respond ONLY with 'Insufficient-Content'. "
        "- For research or academic papers: Use 'Author1&Author2-Year-HumanTitle' format (e.g., 'Smith&Dong-2023-NeuralNets'). Use 'et al.' for 3+ authors. "
        "- For other documents (invoices, legal, bank reports, pensions, court decisions): Use structured, key-based titles. Examples: "
        "  - Invoices: 'ACME-Invoice-123-Dec2023' (good); 'This is an invoice for payment received from customer x on date y' (bad—too verbose). "
        "  - Legal Documents: 'Agreement-Smith-Vs-Jones-2023' (good); 'Long legal agreement between parties A and B dated some time ago without specifics' (bad). "
        "  - Bank Reports: 'Bank-Statement-HSBC-Nov2023' (good); 'Monthly bank report showing transactions for the past 30 days including all fees and interest' (bad). "
        "  - Pensions Yearly Reports: 'Pension-Report-2023-National' (good); 'Detailed yearly pension summary for retirement fund with charts and projections for future benefits' (bad). "
        "  - Court Decisions: 'Court-Ruling-Case-456-2023' (good); 'The court has decided on this legal matter after consideration of all evidence presented by both sides in a complicated case' (bad). "
        "Analyze the text below and output ONLY the filename."
    )
    full_text = prompt + "\n" + pdf_text
    data = {
        "contents": [{"parts": [{"text": full_text}]}]
    }

    url = f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}'
    response = requests.post(url, json=data, headers=headers)

    if response.status_code != 200:
        logging.error(f"API request failed with status code: {response.status_code}")
        logging.error(f"Response: {response.text}")
        return ""

    try:
        response_data = response.json()
        if 'candidates' in response_data and len(response_data['candidates']) > 0:
            text_content = response_data['candidates'][0]['content']['parts'][0]['text']
            return text_content.strip()
        return ""
    except Exception as e:
        logging.error(f"Error parsing API response: {e}")
        return ""


def rename_pdf(pdf_path, api_key, dry_run=False, model='gemini-1.5-flash'):
    """
    Extract PDF text, generate title using Gemini, and rename the file.
    If dry_run is True, only print proposed rename without renaming.
    """
    pdf_text = extract_text_from_first_page(pdf_path)
    if not pdf_text:
        logging.warning("No text extracted from the PDF.")
        return

    new_title = generate_title_with_gemini(pdf_text, api_key, model)
    if not new_title:
        logging.warning(f"Failed to generate a new title for {pdf_path}.")
        return
    if dry_run:
        logging.info(f"Dry run: Would rename '{os.path.basename(pdf_path)}' to '{new_title}'")
        return

    sanitized_title = sanitize_filename(new_title) + ".pdf"
    new_path = os.path.join(os.path.dirname(pdf_path), sanitized_title)

    if not os.path.exists(new_path):
        os.rename(pdf_path, new_path)
        logging.info(f"Renamed to: {new_path}")
    else:
        logging.warning(f"File with name '{sanitized_title}' already exists. Skipping.")


def rename_pdfs_in_directory(directory_path, api_key, dry_run=False, model='gemini-1.5-flash'):
    
   # Iterate through all PDF files in a directory and rename them.
    
        if filename.lower().endswith('.pdf'):
            pdf_path = os.path.join(directory_path, filename)
            logging.info(f"Processing: {pdf_path}")
            try:
                rename_pdf(pdf_path, api_key, dry_run=dry_run, model=model)
            except Exception as e:
                logging.error(f"Error processing {pdf_path}: {e}")


# === Main Execution ===
def main():
    parser = argparse.ArgumentParser(description="Batch rename PDFs using Gemini AI.")
    parser.add_argument('--directory', '-d', required=True,default='.' ,help='Path to directory containing PDFs.')
    parser.add_argument('--api-key', '-k', help='Gemini API key (or set GOOGLE_API_KEY env var).')
    parser.add_argument('--dry-run', action='store_true', help='Preview renames without renaming files.')
    parser.add_argument('--model', '-m', default='gemini-1.5-flash', help='Gemini model (e.g., gemini-1.5-flash).')
    args = parser.parse_args()

    api_key = args.api_key or os.getenv('GOOGLE_API_KEY')
    if not api_key:
        logging.error("API key required via --api-key or GOOGLE_API_KEY env var.")
        return

    rename_pdfs_in_directory(args.directory, api_key, dry_run=args.dry_run, model=args.model)


if __name__ == "__main__":
    main()
