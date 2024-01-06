import plistlib
import sys

if len(sys.argv) < 4:
  sys.exit(1)
loctable, string, lang = sys.argv[1:4]

with open(loctable, 'rb') as fp:
  data = plistlib.load(fp)
  
try:
  key = list(data[lang].keys())[list(data[lang].values()).index(string)]
except ValueError:
  sys.exit(1)

for en in ['en', 'English', 'Base', 'en_GB']:
  if en in data and key in data[en]:
    print(data[en][key], end='')
    sys.exit(0)

sys.exit(1)