if [ -x "$(which lconvert 2>/dev/null)" ]; then
  LCONVERT="$(which lconvert)"
elif [ -x "/usr/local/bin/lconvert" ]; then
  LCONVERT="/usr/local/bin/lconvert"
elif [ -x "/opt/homebrew/bin/lconvert" ]; then
  LCONVERT="/opt/homebrew/bin/lconvert"
elif [ -x "/opt/local/bin/lconvert" ]; then
  LCONVERT="/opt/local/bin/lconvert"
else
    exit 0
fi

${LCONVERT} -i "$1" -of po \
    | awk "/msgid \"$2\"/ { getline; sub(/^msgstr \"/, \"\"); sub(/\"\$/, \"\"); print \$0; exit }" \
    | tr -d "\n"