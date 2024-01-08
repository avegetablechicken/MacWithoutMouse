if [ -x "$(which msgunfmt 2>/dev/null)" ]; then
  MSGUNFMT="$(which msgunfmt)"
elif [ -x "/usr/local/bin/msgunfmt" ]; then
  MSGUNFMT="/usr/local/bin/msgunfmt"
elif [ -x "/opt/homebrew/bin/msgunfmt" ]; then
  MSGUNFMT="/opt/homebrew/bin/msgunfmt"
elif [ -x "/opt/local/bin/msgunfmt" ]; then
  MSGUNFMT="/opt/local/bin/msgunfmt"
else
    exit 0
fi

${MSGUNFMT} "$1" -o - \
    | awk "/msgstr \"$2\"/ { sub(/^msgid \"/, \"\", prevline); sub(/\"\$/, \"\", prevline); print prevline; exit } { prevline = \$0 }" \
    | tr -d "\n"