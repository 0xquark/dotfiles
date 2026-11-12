# Root's shell in lazarus, on top of home/terminal.nix:
# the lab IP in the prompt and window title, and history that survives poweroff if you opt in.
{ lib, ... }:
{
  programs.zsh.initContent = lib.mkAfter ''
    # Opt-in history: when /work/.history exists, zsh history lives there.
    # Atuin's database stays in the VM (SQLite doesn't work over the 9p share).
    # On a throwaway VM it imports the saved history once per boot, so Ctrl+R
    # still sees past sessions; a kept VM (laz -p) has its own atuin database.
    if [ -d /work/.history ]; then
      HISTFILE=/work/.history/zsh_history
      fc -R "$HISTFILE" 2>/dev/null
      if [ "$(findmnt -no FSTYPE /)" = tmpfs ] && [ ! -e /run/atuin-imported ]; then
        touch /run/atuin-imported
        HISTFILE=$HISTFILE atuin import zsh >/dev/null 2>&1
      fi
    fi

    # The HTB VPN address, shown while the tunnel is up:
    #   prompt  [root@lazarus 10.10.14.7:~]$
    #   window  lazarus · 10.10.14.7 · ~
    _lab_ip() {
      LAB_IP=$(ip -4 -o addr show tun0 2>/dev/null | awk '{ split($4, a, "/"); print a[1] }')
      if [ -n "$LAB_IP" ]; then LAB_SEG=" %F{cyan}$LAB_IP%F{red}"; else LAB_SEG=""; fi
    }
    precmd() {
      _lab_ip
      vcs_info
      print -Pn "\e]0;lazarus''${LAB_IP:+ · $LAB_IP} · %~\a"
    }
    PROMPT=$'\n%B%F{red}[%n@%m''${LAB_SEG}:%~''${vcs_info_msg_0_}]$%f%b '
  '';
}
