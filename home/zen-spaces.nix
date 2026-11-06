{ osConfig, pkgs, ... }:
let
  # Zen keeps each space's colours in its session file, next to the tabs.
  # This saves and restores just those colours, one set per desktop theme.
  zen-spaces =
    pkgs.writers.writePython3Bin "zen-spaces"
      {
        libraries = [ pkgs.python3Packages.lz4 ];
        flakeIgnore = [ "E501" ];
      }
      ''
        """Zen space colours per desktop theme.

        zen-spaces save <theme>   remember the current space colours as <theme>
        zen-spaces apply <theme>  put <theme>'s colours back (Zen must be closed)
        zen-spaces sync <theme>   save the theme in use, then apply <theme>
        """
        import configparser
        import json
        import os
        import shutil
        import sys
        from pathlib import Path

        import lz4.block

        ZEN = Path.home() / ".config/zen"
        STATE = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "zen-spaces"
        CURRENT = STATE / "current"
        MAGIC = b"mozLz40\0"


        def profile():
            ini = configparser.ConfigParser()
            ini.read(ZEN / "profiles.ini")
            for section in ini.sections():
                if ini[section].get("Default") == "1" and "Path" in ini[section]:
                    return ZEN / ini[section]["Path"]
            sys.exit("zen-spaces: no default Zen profile found")


        def running(prof):
            # Zen's lock points at "<ip>:+<pid>" while it runs
            try:
                pid = os.readlink(prof / "lock").rsplit("+", 1)[1]
            except (OSError, IndexError):
                return False
            return Path("/proc", pid).exists()


        def read(path):
            data = path.read_bytes()
            if data[:8] != MAGIC:
                sys.exit(f"zen-spaces: {path} is not a Zen session file")
            return json.loads(lz4.block.decompress(data[8:]))


        def write(path, session):
            raw = json.dumps(session, separators=(",", ":"), ensure_ascii=False).encode()
            tmp = path.with_name(path.name + ".tmp")
            tmp.write_bytes(MAGIC + lz4.block.compress(raw))
            tmp.replace(path)


        def save(theme):
            session = read(profile() / "zen-sessions.jsonlz4")
            colours = {
                space["uuid"]: {"name": space.get("name"), "theme": space["theme"]}
                for space in session.get("spaces", [])
                if "theme" in space
            }
            STATE.mkdir(parents=True, exist_ok=True)
            (STATE / f"{theme}.json").write_text(json.dumps(colours, indent=1, ensure_ascii=False))
            print(f"zen-spaces: saved {len(colours)} space colours as {theme}")


        def apply(theme):
            saved_file = STATE / f"{theme}.json"
            if not saved_file.exists():
                print(f"zen-spaces: nothing saved for {theme} yet; Zen keeps its current colours")
                return True
            prof = profile()
            if running(prof):
                print(f"zen-spaces: Zen is open, so its colours stay as they are. Close Zen, then run: zen-spaces sync {theme}")
                return False
            path = prof / "zen-sessions.jsonlz4"
            session = read(path)
            saved = json.loads(saved_file.read_text())
            shutil.copy2(path, STATE / "zen-sessions.before-apply.jsonlz4")
            changed = 0
            for space in session.get("spaces", []):
                if space["uuid"] in saved:
                    space["theme"] = saved[space["uuid"]]["theme"]
                    changed += 1
            write(path, session)
            print(f"zen-spaces: applied {theme} colours to {changed} spaces")
            return True


        def sync(theme):
            current = CURRENT.read_text().strip() if CURRENT.exists() else None
            if current == theme:
                return
            if current:
                save(current)
            if apply(theme):
                STATE.mkdir(parents=True, exist_ok=True)
                CURRENT.write_text(theme)


        if len(sys.argv) != 3 or sys.argv[1] not in ("save", "apply", "sync"):
            sys.exit(__doc__)
        {"save": save, "apply": apply, "sync": sync}[sys.argv[1]](sys.argv[2])
      '';
in
{
  home.packages = [ zen-spaces ];

  # On every switch: remember Zen's colours for the theme being left, restore the new theme's
  home.activation.zenSpaces = ''
    run ${zen-spaces}/bin/zen-spaces sync ${osConfig.theme.name} || true
  '';
}
