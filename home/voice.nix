# The Whisper model and the voice pill, shared by dictation and Joi
{ config, pkgs }:
let
  c = config.lib.stylix.colors.withHashtag;

  model = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin";
    sha256 = "0p8yqkwvpl9lyy43yajk305bps0v5z1qgyg0jwh35j7cb1nqs4y6";
  };

  # A small pill above the bottom bar. It opens as a smiley whose smile turns
  # into bars that bounce with your voice, ripples while Whisper works (SIGUSR1),
  # then smiles again and closes itself (SIGUSR2).
  pillScript = pkgs.writeScript "dictate-pill" ''
    #!${pkgs.python3.withPackages (ps: [ ps.pygobject3 ps.pycairo ])}/bin/python3
    import array
    import math
    import os
    import signal
    import sys
    import time

    import cairo
    import gi

    gi.require_version("Gtk", "3.0")
    gi.require_version("GtkLayerShell", "0.1")
    gi.require_version("GLibUnix", "2.0")
    gi.require_foreign("cairo")
    from gi.repository import GLib, GLibUnix, Gtk, GtkLayerShell  # noqa: E402

    WAV = sys.argv[1]
    W, H = 60, 22
    DOTS = [0.55, 0.85, 1.0, 0.85, 0.55]  # taller in the middle

    # `dictate-pill WAV joi`: the pill rises out of Joi's face at the right end
    # of the bottom bar, and sinks back into it when done
    JOI = sys.argv[2:3] == ["joi"]
    BAR = 26  # height of the bottom bar
    WIN_H = BAR + 10 + H + 4 if JOI else H


    def rgb(hex_color):
        return tuple(int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))


    BG, BORDER, DOT = rgb("${c.base00}"), rgb("${c.base02}"), rgb("${c.base0E}")

    start = None  # set on the first frame, once the pill is on screen
    level = 0.0
    thinking = False
    done_at = None


    def read_level():
        # Loudness of the last 50ms that pw-record wrote
        try:
            size = os.path.getsize(WAV)
            if size < 44 + 1600:
                return 0.0
            with open(WAV, "rb") as f:
                f.seek((size - 1600) & ~1)
                samples = array.array("h", f.read(1600))
        except OSError:
            return 0.0
        rms = math.sqrt(sum(s * s for s in samples) / max(len(samples), 1))
        return min(1.0, rms / 3000) ** 0.6


    def rounded(cr, x, y, w, h, r):
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()


    def blob(cr, cx, cy, w, h):
        w, h = max(w, 0.0), max(h, 0.0)
        if w > 0 and h > 0:
            rounded(cr, cx - w / 2, cy - h / 2, w, h, min(w, h) / 2)
            cr.fill()


    def lerp(a, b, k):
        return a + (b - a) * k


    def clamp(x):
        return max(0.0, min(1.0, x))


    def springy(x):
        # Ease out with a small overshoot
        x -= 1
        return 1 + 2.7 * x ** 3 + 1.7 * x ** 2


    def bar_height(i, t):
        if thinking:
            return 4 + 6 * max(0.0, math.sin(t * 7 - i * 0.8)) ** 2
        wobble = 0.75 + 0.25 * math.sin(t * 9 + i * 1.3)
        breathe = 0.6 * (1 + math.sin(t * 3 - i * 0.6))
        return 4 + breathe + 10 * level * DOTS[i] * wobble


    def draw(_widget, cr):
        global start
        if start is None:
            start = time.monotonic()
        t = time.monotonic() - start
        cr.set_operator(cairo.OPERATOR_CLEAR)
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)

        # m runs from smiley (0) to bars (1): in after a beat, back out when done
        if done_at is None:
            m = springy(clamp((t - 0.5) / 0.35))
            p = min(1.0, t / 0.18)
            scale = 1 + 0.15 * math.sin(p * math.pi) - 0.3 * (1 - p) ** 2
            rise = springy(clamp(t / 0.35))
        elif JOI:
            d = t - done_at
            m = 1 - springy(clamp(d / 0.3))
            scale = 1
            rise = 1 - clamp((d - 0.5) / 0.3) ** 2
            if rise <= 0:
                Gtk.main_quit()
                return
        else:
            d = t - done_at
            m = 1 - springy(clamp(d / 0.3))
            scale = 1 - springy(clamp((d - 0.6) / 0.2))
            if scale <= 0.02:
                Gtk.main_quit()
                return
        if JOI:
            # From the middle of the bar up to its spot above it
            cr.translate(0, lerp(WIN_H - BAR / 2 - H / 2, WIN_H - BAR - 10 - H, rise))
            scale *= lerp(0.35, 1, rise)
        cr.translate(W / 2, H / 2)
        cr.scale(scale, scale)
        cr.translate(-W / 2, -H / 2)

        rounded(cr, 0.5, 0.5, W - 1, H - 1, (H - 1) / 2)
        cr.set_source_rgb(*BG)
        cr.fill_preserve()
        cr.set_source_rgb(*BORDER)
        cr.set_line_width(1)
        cr.stroke()

        cr.set_source_rgb(*DOT)
        # Eyes, with one blink while the face is showing
        blink = 0.2 if 0.28 < t < 0.38 else 1.0
        eye = 3 * clamp(1 - m)
        for side in (-1, 1):
            blob(cr, W / 2 + side * 4, 6.5, eye, eye * blink)

        # The smile's dots slide up and stretch into the bars
        for i in range(5):
            a = math.radians(150 - 30 * i)
            sx, sy = W / 2 + 7 * math.cos(a), 9 + 7 * math.sin(a)
            bx, by = W / 2 + (i - 2) * 8, H / 2
            blob(cr, lerp(sx, bx, m), lerp(sy, by, m),
                 lerp(2.4, 4, m), lerp(2.4, bar_height(i, t), m))


    def tick(area):
        global level
        if not thinking:
            # Rise fast, fall slowly, so the bars feel springy
            level = max(read_level(), level * 0.85)
        area.queue_draw()
        return True


    def think():
        global thinking
        thinking = True
        return True


    def done():
        global done_at
        if done_at is None and start is not None:
            done_at = time.monotonic() - start
        return True


    win = Gtk.Window()
    win.set_app_paintable(True)
    win.set_visual(win.get_screen().get_rgba_visual())
    GtkLayerShell.init_for_window(win)
    GtkLayerShell.set_namespace(win, "dictate")
    GtkLayerShell.set_layer(win, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.BOTTOM, True)
    if JOI:
        # Reach down over the bar, so the pill can start inside it
        GtkLayerShell.set_anchor(win, GtkLayerShell.Edge.RIGHT, True)
        GtkLayerShell.set_exclusive_zone(win, -1)
    else:
        GtkLayerShell.set_margin(win, GtkLayerShell.Edge.BOTTOM, 10)
    win.set_size_request(W, WIN_H)

    area = Gtk.DrawingArea()
    area.connect("draw", draw)
    win.add(area)
    win.show_all()
    win.input_shape_combine_region(cairo.Region())  # clicks pass through

    GLib.timeout_add(16, tick, area)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, think)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR2, done)
    # Exit straight away, even if the main loop hasn't started yet
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: os._exit(0))
    GLib.timeout_add_seconds(600, Gtk.main_quit)  # in case the stop never comes
    Gtk.main()
  '';

  # wrapGAppsHook finds the GTK and layer-shell libraries for the script
  pill = pkgs.stdenv.mkDerivation {
    name = "dictate-pill";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.wrapGAppsHook3 pkgs.gobject-introspection ];
    buildInputs = [ pkgs.gtk3 pkgs.gtk-layer-shell ];
    installPhase = "install -Dm755 ${pillScript} $out/bin/dictate-pill";
  };
in
{
  inherit model pill;
}
