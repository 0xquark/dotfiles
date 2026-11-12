# Lazarus: a throwaway microVM for HTB and untrusted code.
# It reads the host's /nix/store, so the tools aren't downloaded again,
# and its root disk lives in RAM, so nothing is left after it stops.
# Start: laz (laz -p 3d keeps it for 3 days)    More shells: laz sh    Leave: poweroff
{ inputs, pkgs, ... }:
let
  # Serial consoles can't pass the window size, so ask the terminal for it.
  # Runs at login; run `fit` again after resizing the window.
  fit = pkgs.writeShellScriptBin "fit" ''
    old=$(stty -g)
    stty raw -echo min 0 time 5
    printf '\e[18t' > /dev/tty
    IFS=';' read -r -d t _ rows cols < /dev/tty
    stty "$old"
    [ -n "$cols" ] && stty rows "$rows" cols "$cols"
  '';

  htb = pkgs.writeShellApplication {
    name = "htb";
    runtimeInputs = with pkgs; [
      openvpn
      iproute2
      gawk
      fzf
    ];
    text = builtins.readFile ./htb.sh;
  };

  # Files to hand to a box with `serve`. Release builds are pinned by hash;
  # chisel is rebuilt without cgo so it runs on any Linux box.
  kit = pkgs.linkFarm "htb-kit" {
    "linpeas.sh" = pkgs.fetchurl {
      url = "https://github.com/peass-ng/PEASS-ng/releases/download/20261019-e0064253/linpeas.sh";
      hash = "sha256-N6Ftsif+TS/KR8CV8PtRKpalyQTzA/D5kODywrBc8Ic=";
    };
    pspy64 = pkgs.fetchurl {
      url = "https://github.com/DominicBreuker/pspy/releases/download/v1.2.1/pspy64";
      hash = "sha256-yT8ppcwTR725DhShJCTmRpyM/qmiC4ALwkl1XwBDo7s=";
    };
    chisel = "${
      pkgs.chisel.overrideAttrs (old: {
        env = (old.env or { }) // {
          CGO_ENABLED = "0";
        };
      })
    }/bin/chisel";
    ligolo-agent = "${pkgs.ligolo-ng}/bin/ligolo-agent";
  };

  # Daily HTB helpers, each in its own .sh file next to this one
  helper =
    name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile ./${name}.sh;
    };
  scan = helper "scan" [
    pkgs.nmap
    pkgs.gnugrep
  ];
  addhost = helper "addhost" [ pkgs.gawk ];
  serve = pkgs.writeShellApplication {
    name = "serve";
    runtimeInputs = with pkgs; [
      python3
      iproute2
      gawk
    ];
    text = "kit=${kit}
" + builtins.readFile ./serve.sh;
  };
in
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  networking.hostName = "lazarus";

  microvm = {
    hypervisor = "qemu"; # has 9p built in, so the host needs no extra daemons
    vcpu = 4;
    mem = 4096;
    shares = [
      {
        proto = "9p";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }
      # The only host folder the VM can write to
      {
        proto = "9p";
        tag = "work";
        source = "/home/drquark/oasis/basement/work";
        mountPoint = "/work";
      }
    ];
    # User-mode networking: the VM gets internet through QEMU, with no bridge or root on the host
    interfaces = [
      {
        type = "user";
        id = "qemu";
        mac = "02:00:00:00:00:01";
      }
    ];
    # Burp on the host reaches the HTB network through the SOCKS proxy in here
    forwardPorts = [
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 1080;
        guest.port = 1080;
      }
      # SSH, for more shells: `laz sh` on the host
      {
        from = "host";
        host.address = "127.0.0.1";
        host.port = 2222;
        guest.port = 22;
      }
    ];
  };

  environment.systemPackages =
    import ../../home/basement-tools.nix pkgs
    ++ (with pkgs; [
      openvpn
      netcat-openbsd # the nc from Kali, so `nc -lvnp 4444` from writeups works
      python3
      curl
      git
      ghostty.terminfo
      # Pivoting, and catching responses on the lab network
      ligolo-ng
      chisel
      responder
      rlwrap
    ])
    ++ [
      fit
      htb
      scan
      addhost
      serve
    ];

  systemd.services.socks = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = "${pkgs.microsocks}/bin/microsocks -p 1080";
  };

  # SecLists where Kali keeps it, so wordlist paths from writeups work as they are
  systemd.tmpfiles.rules = [
    "L+ /usr/share/seclists - - - - ${pkgs.seclists}/share/wordlists/seclists"
  ];
  environment.variables.SECLISTS = "/usr/share/seclists";

  # Key-only SSH. laz puts the host's key in /work/.lazarus before the VM starts.
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Leaves port 5355 free for Responder
  services.resolved.settings.Resolve.LLMNR = false;

  # /etc/hosts as a real file, so addhost can write to it
  environment.etc.hosts.mode = "0644";

  # At boot: take the SSH key from laz, bring back the boxes from addhost,
  # and clear the lab IP that Waybar shows until `htb up` sets it again
  systemd.services.lazarus-boot = {
    wantedBy = [ "multi-user.target" ];
    before = [ "sshd.service" ];
    unitConfig.RequiresMountsFor = "/work";
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p /work/.lazarus
      rm -f /work/.lazarus/lab-ip
      if [ -f /work/.lazarus/authorized_keys ]; then
        install -D -m 600 /work/.lazarus/authorized_keys /root/.ssh/authorized_keys
      fi
      if [ -f /work/hosts ]; then
        cat /work/hosts >> /etc/hosts
      fi
    '';
  };

  # Reverse shells from HTB boxes need to reach listeners in here
  networking.firewall.enable = false;

  # Straight to a root shell on start; the VM is the sandbox
  services.getty.autologinUser = "root";
  users.users.root.password = "";

  # The same zsh, prompt and tools as on the host (home/terminal.nix),
  # plus the lab IP and opt-in history (shell.nix)
  programs.zsh.enable = true;
  users.users.root.shell = pkgs.zsh;
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.root = {
      imports = [
        ../../home/terminal.nix
        ./shell.nix
      ];
      home.stateVersion = "26.05";
    };
  };

  # Ghostty's terminfo (in the package list above), so colours, keys and
  # full-screen tools work like on the host
  systemd.services."serial-getty@".environment.TERM = "xterm-ghostty";

  # On the console only: fit it to the window, then show Gargantua and the mission name.
  # SSH shells get the window size from ssh and skip the banner.
  environment.loginShellInit = ''
    if [ -z "$SSH_CONNECTION" ]; then
      fit
      bash ${./banner.sh}
    fi
  '';

  system.stateVersion = "26.05";
}
