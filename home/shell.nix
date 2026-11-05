{ ... }:

{
  # Keeps unlocked keys in memory for the session
  services.ssh-agent.enable = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    # Option names are the same as in ~/.ssh/config (see `man ssh_config`)
    settings = {
      # Applies to every host
      "*" = {
        AddKeysToAgent = "yes";
        IdentitiesOnly = true;   # offer ONLY the key listed for that host
      };

      # ── Personal ───────────────────────────────
      "github.com" = {
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519_personal";
      };

      # ── KDE ────────────────────────────────────
      "invent.kde.org" = {
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519_kde";
      };

      # ── CERN ───────────────────────────────────
      "gitlab.cern.ch" = {
        User = "git";
        Port = 7999;             # CERN GitLab uses SSH on port 7999
        IdentityFile = "~/.ssh/id_ed25519_cern";
      };
      "lxplus" = {               # ssh lxplus
        HostName = "lxplus.cern.ch";
        User = "karanjot";
        IdentityFile = "~/.ssh/id_ed25519_cern";
      };
    };
  };

  # Bash, set up by Home Manager (loads the aliases below)
  programs.bash.enable = true;

  # Short commands for the terminal
  home.shellAliases = {
    nap = "systemctl suspend";
  };
}
