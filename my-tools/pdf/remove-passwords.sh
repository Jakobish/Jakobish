#!/bin/bash
PASSWORD="387143"
PASSWORD="708480"
PASSWORD="426236"




for file in *.pdf; do
  qpdf --password=$PASSWORD --decrypt "$file" "$PASSWORD-decrypted-$file"
done