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
    | awk "/msgid \"$2\"/ { getline nextline; sub(/^msgstr \"/, \"\", nextline); sub(/\"\$/, \"\", nextline); print nextline; exit }" \
    | tr -d "\n"