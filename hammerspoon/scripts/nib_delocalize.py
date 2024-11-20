import sys
import unicodedata

def is_printable(char):
    return not unicodedata.category(char).startswith('C')

def contains_unicode(line):
    return any(ord(char) > 127 for char in line)

def filter_line(text):
    current_line = []

    for char in text:
        if is_printable(char):
            current_line.append(char)
        else:
            if contains_unicode(current_line) or len(current_line) >= 3:
                return ''.join(current_line)
            else:
                current_line = []
    
    if contains_unicode(current_line) or len(current_line) >= 3:
        return ''.join(current_line)

string, en_file_path, file_path = sys.argv[1:4]

with open(file_path, 'rb') as f:
    content = f.read().decode('utf-8', errors='ignore') 
start = False
lines = []
for line in content.split('\n'):
    filtered = filter_line(line)
    if filtered == '_NSWindowsMenu':
        break
    if start and filtered is not None and len(filtered) > 0:
        lines.append(filtered)
    if filtered == '_NSAppleMenu':
        start = True

with open(en_file_path, 'rb') as f:
    content = f.read().decode('utf-8', errors='ignore') 
start = False
en_lines = []
for line in content.split('\n'):
    filtered = filter_line(line)
    if filtered == '_NSWindowsMenu':
        break
    if start and filtered is not None and len(filtered) > 0:
        en_lines.append(filtered)
    if filtered == '_NSAppleMenu':
        start = True

if len(lines) == len(en_lines):
    for loc, en in zip(lines, en_lines):
        if loc == string:
            print(en, end='')
            sys.exit(0)
sys.exit(1)
