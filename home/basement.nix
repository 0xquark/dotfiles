# The basement: bug bounty and HTB tools on the host.
# Untrusted code runs in the lazarus VM instead (`laz`).
{ lib, pkgs, ... }:
let
  # laz: lazarus in the current terminal, with the background darkened while you're in it
  laz = pkgs.writeShellApplication {
    name = "laz";
    runtimeInputs = with pkgs; [
      coreutils
      procps
      openssh
      wl-clipboard
      libnotify
    ];
    text = ''
      ghostty=${pkgs.ghostty}/bin/ghostty
    ''
    + builtins.readFile ./laz.sh;
  };
in
{
  home.packages =
    import ./basement-tools.nix pkgs
    ++ (with pkgs; [
      # GUI tools stay on the host; the VM has no screen
      burpsuite
      caido-desktop
      ghidra
      codeql
    ])
    ++ [ laz ];

  # Same name as in lazarus, e.g. ffuf -w $SECLISTS/Discovery/Web-Content/common.txt
  programs.zsh.sessionVariables.SECLISTS = "${pkgs.seclists}/share/wordlists/seclists";

  # Deletes a kept lazarus (laz -p) once its time is up, even if laz isn't run again
  systemd.user.services.laz-gc = {
    Unit.Description = "Delete the kept lazarus VM when its time is up";
    Service = {
      Type = "oneshot";
      ExecStart = "${laz}/bin/laz gc";
    };
  };
  systemd.user.timers.laz-gc = {
    Unit.Description = "Check the kept lazarus VM every hour";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Waybar: LAZ while lazarus runs, LAZ 10.10.14.7 once `htb up` connects.
  # Red while lazarus runs. Click for a lazarus shell, right-click to copy the lab IP.
  # Its place in the bar is set in bar.nix.
  programs.waybar.settings.main."custom/lazarus" = {
    exec = "${laz}/bin/laz bar";
    return-type = "json";
    interval = 5;
    on-click = "${laz}/bin/laz open";
    on-click-right = "${laz}/bin/laz copy-ip";
  };
  programs.waybar.style = lib.mkAfter ''
    /* Red like root's prompt in the VM: you're in the danger zone */
    #custom-lazarus {
      padding: 0 5px;
      color: @base08;
    }
  '';
}
