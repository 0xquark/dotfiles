{ inputs, ... }:

{
  imports = [ inputs.nix-index-database.homeModules.nix-index ];

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
        IdentitiesOnly = true; # offer ONLY the key listed for that host
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
        Port = 7999; # CERN GitLab uses SSH on port 7999
        IdentityFile = "~/.ssh/id_ed25519_cern";
      };
      "lxplus" = {
        # ssh lxplus
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
    cat = "bat --paging=never"; # cat with colours and line numbers
  };

  # ── Terminal tools (how-to: docs/terminal-tools.md) ──
  # Prompt with git branch, language versions and how long a command took
  programs.starship.enable = true;

  # z <part of a folder name> jumps there; zi picks from a list
  programs.zoxide.enable = true;

  # Ctrl+R: search history, Ctrl+T: pick a file, Alt+C: jump into a folder
  programs.fzf.enable = true;

  # ls with colours, icons and git status (ls, ll, la, lt)
  programs.eza = {
    enable = true;
    icons = "auto";
    git = true;
  };

  # cat with syntax highlighting
  programs.bat.enable = true;

  # Per-project tools: cd into a folder with a .envrc and its packages load
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true; # caches the environment, so cd is instant
  };

  # , <program> runs anything from nixpkgs without installing it;
  # unknown commands tell you which package has them
  programs.nix-index-database.comma.enable = true;
}
