# zsh and the terminal tools. The host and the lazarus VM both use this file,
# so host-only things (SSH, direnv, comma) stay in shell.nix.
{ pkgs, ... }:

{
  # Bash, for scripts and nix-shell (the aliases below work in both shells)
  programs.bash.enable = true;

  # Short commands for the terminal
  home.shellAliases = {
    cat = "bat --paging=never"; # cat with colours and line numbers
  };

  # zsh: the login shell (set in configuration.nix)
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true; # grey suggestion from history; → accepts it
    syntaxHighlighting.enable = true; # commands turn red while misspelled
    history = {
      size = 100000;
      save = 100000;
      share = true; # every open terminal sees the others' commands
      ignoreDups = true;
    };
    # The old NixOS prompt, plus the git branch:
    # [drquark@delorean:~/nixos (main)]$   (red as root)
    initContent = ''
      zstyle ':completion:*' menu select   # Tab opens a menu you move through with the arrows

      autoload -Uz vcs_info
      zstyle ':vcs_info:*' enable git
      zstyle ':vcs_info:git:*' formats ' (%b)'
      setopt prompt_subst
      precmd() {
        vcs_info
        print -Pn "\e]0;%n@%m: %~\a"   # window title, shown in Waybar
      }
      PROMPT=$'\n%B%(!.%F{red}.%F{green})[%n@%m:%~''${vcs_info_msg_0_}]$%f%b '
    '';
  };

  # ── Terminal tools  ──
  # z <part of a folder name> jumps there; zi picks from a list
  programs.zoxide.enable = true;

  # Ctrl+R: search history, Ctrl+T: pick a file, Alt+C: jump into a folder
  # (Ctrl+R is atuin's, below.) File and folder lists come from fd, so they skip .gitignored files
  programs.fzf = {
    enable = true;
    fileWidgetCommand = "fd --type f";
    changeDirWidgetCommand = "fd --type d";
  };

  # ls with colours, icons and git status (ls, ll, la, lt)
  programs.eza = {
    enable = true;
    icons = "auto";
    git = true;
  };

  # cat with syntax highlighting
  programs.bat.enable = true;

  # fd: find files by name, fast; jq: read and filter JSON
  home.packages = with pkgs; [
    fd
    jq
  ];

  # tldr <command>: short help pages made of examples (refreshed automatically)
  programs.tealdeer.enable = true;

  # yazi: file manager in the terminal; `y` opens it, and you stay in the folder you quit in
  programs.yazi.enable = true;

  # atuin: Ctrl+R searches every command you've run, with folder, time and exit status
  programs.atuin = {
    enable = true;
    flags = [ "--disable-up-arrow" ]; # ↑ stays the plain previous command
    settings = {
      style = "compact";
      inline_height = 20; # opens under the prompt, not full screen
      enter_accept = false; # Enter puts the command on the line so you can edit it first
      update_check = false; # updates come with Nix
    };
  };
}
