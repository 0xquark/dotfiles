# addhost: give a box its names, e.g. addhost 10.10.11.42 box.htb dev.box.htb
# The entry also goes in /work/hosts, so it comes back after a reboot.
# A name that is already listed moves to the new IP. With no arguments, lists the boxes.
saved=/work/hosts

if [ $# -eq 0 ]; then
  cat "$saved" 2>/dev/null || echo "No boxes yet. Add one with: addhost <ip> <name>..."
  exit
fi
if [ $# -lt 2 ] || ! [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: addhost <ip> <name>..." >&2
  exit 1
fi
ip=$1
shift

# Takes the names off every line, and drops lines that have no name left
without_names() {
  awk -v names="$*" '
    BEGIN { split(names, list, " "); for (i in list) drop[list[i]] = 1 }
    /^[[:space:]]*(#|$)/ { print; next }
    {
      line = $1; kept = 0
      for (i = 2; i <= NF; i++) if (!($i in drop)) { line = line " " $i; kept++ }
      if (kept) print line
    }'
}

for f in /etc/hosts "$saved"; do
  touch "$f"
  rest=$(without_names "$@" < "$f")
  printf '%s\n%s\n' "$rest" "$ip $*" | sed '/./,$!d' > "$f"
done
echo "$ip $*"
