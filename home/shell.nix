{ ... }:
{
  # Keeps unlocked keys in memory for the session
  services.ssh-agent.enable = true;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      # Applies to every host
      "*" = {
        addKeysToAgent = "yes";
        identitiesOnly = true;   # offer ONLY the key listed for that host
      };

      # ── Personal ───────────────────────────────
      "github.com" = {
        user = "git";
        identityFile = "~/.ssh/id_ed25519_personal";
      };

      # ── KDE ────────────────────────────────────
      "invent.kde.org" = {
        user = "git";
        identityFile = "~/.ssh/id_ed25519_kde";
      };

      # ── CERN ───────────────────────────────────
      "gitlab.cern.ch" = {
        user = "git";
        port = 7999;             # CERN GitLab uses SSH on port 7999
        identityFile = "~/.ssh/id_ed25519_cern";
      };
      "lxplus" = {               # ssh lxplus
        hostname = "lxplus.cern.ch";
        user = "karanjot";
        identityFile = "~/.ssh/id_ed25519_cern";
      };
    };
  };
}
