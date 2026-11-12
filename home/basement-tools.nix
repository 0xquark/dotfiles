# Command-line tools for bug bounty and HTB.
# The host installs them in home/basement.nix, and the lazarus VM uses the same list.
pkgs: with pkgs; [
  # Recon and fuzzing
  nmap
  ffuf
  feroxbuster
  subfinder
  httpx
  katana
  nuclei
  seclists
  # Exploiting
  sqlmap
  jwt-hack
  flask-unsign
  git-dumper
  exploitdb
  hashcat
  john
  # Windows and Active Directory boxes
  netexec
  python3Packages.impacket # secretsdump.py, GetUserSPNs.py, psexec.py, ...
  evil-winrm
  bloodhound-py
  kerbrute
  enum4linux-ng
  smbmap
  # Code review
  semgrep
  gitleaks
  trufflehog
]
