# Cloak: makes Claude Code look like a plain shell.
# `cloak on` / `cloak off` switches it. The change shows the next time you start `claude`.
# Cloak adds its own settings file with --settings, so ~/.claude/settings.json keeps your own setup.
{ config, lib, pkgs, ... }:

let
  claude = "${config.programs.claude-code.finalPackage}/bin/claude";
  grey = "ansi:white";

  # Shows the zsh prompt from terminal.nix above Claude's "$" prompt
  statusline = pkgs.writeShellApplication {
    name = "claude-cloak-statusline";
    runtimeInputs = [ pkgs.jq pkgs.git ];
    text = ''
      dir=$(jq -r '.workspace.current_dir // .cwd')
      branch=$(git -C "$dir" branch --show-current 2>/dev/null || true)
      printf '\e[1;32m[%s@%s:%s%s]\e[0m' "$USER" "$(< /proc/sys/kernel/hostname)" \
        "''${dir/#$HOME/\~}" "''${branch:+ ($branch)}"
    '';
  };

  settings = pkgs.writeText "claude-cloak-settings.json" (builtins.toJSON {
    theme = "custom:cloak";
    # Screen-reader mode draws flat text: no logo, no input box, and "$" as the prompt
    axScreenReader = true;
    # The classic renderer prints into the normal screen, so the terminal's scrollback works.
    # Fullscreen switches to the alternate screen, and screen-reader mode has no scrolling there.
    tui = "default";
    prefersReducedMotion = true;
    spinnerTipsEnabled = false;
    spinnerVerbs = {
      mode = "replace";
      verbs = [ "Compiling" "Linking" "Indexing" "Resolving" "Building" "Checking" ];
    };
    outputStyle = "cloak";
    statusLine = {
      type = "command";
      command = lib.getExe statusline;
    };
  });

  cloak = pkgs.writeShellScriptBin "cloak" ''
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/claude-cloak"
    case "''${1:-status}" in
      on) mkdir -p "''${state%/*}" && touch "$state" ;;
      off) rm -f "$state" ;;
      status) ;;
      run)
        shift
        if [ -e "$state" ]; then
          export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 # keep the zsh window title
          exec ${claude} --settings ${settings} "$@"
        fi
        exec ${claude} "$@"
        ;;
      *) echo "usage: cloak [on|off|status]" >&2; exit 1 ;;
    esac
    if [ -e "$state" ]; then echo "cloak: on"; else echo "cloak: off"; fi
  '';
in
{
  home.packages = [ cloak ];
  home.shellAliases.claude = "cloak run";

  # The ANSI base takes its colours from the terminal palette (Stylix), so status
  # colours look like any other shell tool. The overrides remove Claude's orange
  # and the shaded blocks behind messages.
  home.file.".claude/themes/cloak.json".text = builtins.toJSON {
    name = "Cloak";
    base = "dark-ansi";
    overrides = {
      claude = grey;
      claudeShimmer = grey;
      clawd_body = grey;
      briefLabelClaude = grey;
      fastMode = grey;
      fastModeShimmer = grey;
      orange_FOR_SUBAGENTS_ONLY = grey;
      # Diff colours are line backgrounds. Plain lines and red/green on the changed words only.
      diffAdded = "ansi:black";
      diffRemoved = "ansi:black";
      diffAddedDimmed = "ansi:black";
      diffRemovedDimmed = "ansi:black";
      diffAddedWord = "ansi:green";
      diffRemovedWord = "ansi:red";
      userMessageBackground = "ansi:black";
      userMessageBackgroundHover = "ansi:black";
      bashMessageBackgroundColor = "ansi:black";
      memoryBackgroundColor = "ansi:black";
    };
  };

  # Replies that read like command output
  programs.claude-code.outputStyles.cloak = ''
    ---
    name: cloak
    description: Terse replies that read like command-line tool output
    keep-coding-instructions: true
    ---
    Write every reply like the output of a command-line tool.

    - Use no greetings, sign-offs or first person ("I", "I'll", "Let me").
    - Report work as short status lines, e.g. "patched home/keys.nix (2 lines)", "build ok", "error: foo.c:12: missing semicolon".
    - Answer questions in as few lines as possible.
    - Use no emoji and no markdown headings.
  '';
}
