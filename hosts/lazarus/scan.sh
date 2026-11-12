# scan: the two nmap passes every box starts with.
#   scan 10.10.11.42 [name]   all TCP ports fast, then scripts and versions on the open ones
#   scan box.htb              the name comes from the target: /work/boxes/box/scans
if [ $# -lt 1 ]; then
  echo "usage: scan <ip or host> [name]" >&2
  exit 1
fi
target=$1
name=${2:-${target%.htb}}
name=${name//\//_}
out=/work/boxes/$name/scans
mkdir -p "$out"

echo "── all TCP ports on $target ──"
nmap -p- --min-rate 2000 -T4 -Pn --open -oA "$out/ports" "$target"
ports=$(grep -oE '[0-9]+/open' "$out/ports.gnmap" | cut -d/ -f1 | paste -sd, || true)
if [ -z "$ports" ]; then
  echo "No open TCP ports. Is the VPN up (htb ip) and the box started?" >&2
  exit 1
fi

echo
echo "── scripts and versions on $ports ──"
nmap -sC -sV -Pn -p "$ports" -oA "$out/services" "$target"
echo
echo "Saved in $out (~/oasis/basement/work/boxes/$name/scans on the host)"
