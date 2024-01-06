import plistlib
import sys

if len(sys.argv) < 4:
  sys.exit(1)
loctable, string, lang = sys.argv[1:4]

with open(loctable, 'rb') as fp:
  data = plistlib.load(fp)

if lang not in data:
  sys.exit(1)

if data[lang].get(string):
  print(data[lang][string], end='')
  sys.exit(0)
else:
  if lang == 'en':
    for en in ['English', 'Base', 'en_GB']:
      if en in data and data[en].get(string):
        print(data[en][string], end='')
        sys.exit(0)

for en in ['en', 'English', 'Base', 'en_GB']:
  if en in data:
    try:
      key = list(data[en].keys())[list(data[en].values()).index(string)]
      print(data[lang][key], end='')
      sys.exit(0)
    except ValueError:
      pass

sys.exit(1)
