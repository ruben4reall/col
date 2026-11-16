/* The island's look. It is always dark, whatever the desktop's style: the night of Col's brand, white text, and the
 * desktop's own accent colour for what is on. */

namespace Col.Style {
    const string CSS = """
window.col-island,
window.col-island > .col-island-view {
  background: none;
  box-shadow: none;
}

.col-island-content {
  color: white;
  font-size: 13px;
}

.col-accent {
  color: @accent_bg_color;
}

.col-top-bar {
  margin: 9px 14px 2px 14px;
  min-height: 30px;
}

.col-island-content button.col-glyph {
  background: none;
  border: none;
  box-shadow: none;
  outline: none;
  color: white;
  min-width: 26px;
  min-height: 26px;
  padding: 3px;
  border-radius: 999px;
}

.col-island-content button.col-glyph:hover {
  background-color: alpha(white, 0.1);
}

.col-island-content button.col-glyph:active {
  background-color: alpha(white, 0.18);
}

.col-island-content button.col-glyph:disabled {
  color: alpha(white, 0.3);
}

.col-island-content button.col-tab {
  color: alpha(white, 0.45);
  min-width: 30px;
}

.col-island-content button.col-tab.selected {
  color: white;
  background-color: alpha(white, 0.12);
}

.col-island-content button.col-tab.col-attention {
  color: #FF9F0A;
}

.col-island-content button.col-play {
  min-width: 40px;
  min-height: 40px;
}

.col-battery-label {
  font-size: 12px;
  font-weight: 600;
  color: alpha(white, 0.75);
  font-feature-settings: "tnum";
}

.col-music {
  margin: 0 20px 16px 20px;
}

.col-title {
  font-weight: 700;
  font-size: 15px;
}

.col-row-title {
  font-weight: 600;
  font-size: 13px;
}

.col-subtitle {
  color: alpha(white, 0.55);
  font-size: 13px;
}

.col-hint {
  color: alpha(white, 0.45);
  font-size: 12px;
}

.col-heading {
  color: alpha(white, 0.5);
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.04em;
}

.col-time {
  color: alpha(white, 0.5);
  font-size: 11px;
  font-weight: 600;
  font-feature-settings: "tnum";
}

.col-clock {
  font-size: 44px;
  font-weight: 300;
  font-feature-settings: "tnum";
}

.col-countdown {
  font-size: 30px;
  font-weight: 600;
  color: #FF9F0A;
  font-feature-settings: "tnum";
}

.col-card {
  background-color: alpha(white, 0.06);
  border: 1px solid alpha(#FF9F0A, 0.4);
  border-radius: 20px;
  padding: 12px 14px;
}

.col-badge {
  background-color: alpha(white, 0.1);
  border-radius: 999px;
  padding: 1px 8px;
  font-size: 12px;
  font-weight: 600;
  color: alpha(white, 0.7);
}

.col-command {
  background-color: alpha(white, 0.08);
  border-radius: 10px;
}

.col-command-text {
  font-family: monospace;
  font-size: 12.5px;
  padding: 6px 10px;
  color: white;
}

.col-island-content button.col-allow,
.col-island-content button.col-deny,
.col-island-content button.col-chip {
  border: none;
  box-shadow: none;
  border-radius: 999px;
  font-weight: 700;
  min-height: 30px;
  padding: 0 18px;
}

.col-island-content button.col-allow {
  background-color: white;
  background-image: none;
  color: black;
}

.col-island-content button.col-allow:hover {
  background-color: alpha(white, 0.88);
}

.col-island-content button.col-allow:disabled {
  background-color: alpha(white, 0.25);
  color: alpha(black, 0.6);
}

.col-island-content button.col-deny {
  background-color: alpha(white, 0.16);
  background-image: none;
  color: white;
}

.col-island-content button.col-deny:hover {
  background-color: alpha(white, 0.24);
}

.col-island-content button.col-chip {
  background-color: alpha(white, 0.1);
  background-image: none;
  color: white;
  font-weight: 600;
  min-height: 28px;
  padding: 0 10px;
}

.col-island-content button.col-chip:hover {
  background-color: alpha(white, 0.18);
}

.col-island-content button.col-link {
  background: none;
  border: none;
  box-shadow: none;
  color: alpha(white, 0.55);
  font-weight: 600;
  padding: 0 4px;
}

.col-island-content button.col-link:hover {
  color: white;
}

.col-island-content button.col-round {
  background-color: alpha(white, 0.12);
}

.col-row {
  padding: 5px 0;
}

.col-island-content button.col-clip-text {
  background: none;
  border: none;
  box-shadow: none;
  color: alpha(white, 0.9);
  font-weight: 400;
  padding: 3px 6px;
  border-radius: 8px;
  min-height: 24px;
}

.col-island-content button.col-clip-text:hover {
  background-color: alpha(white, 0.08);
}

.col-island-content button.col-pin {
  color: alpha(white, 0.35);
}

.col-island-content button.col-pin.pinned {
  color: #FF9F0A;
}

.col-island-content switch {
  background-color: alpha(white, 0.2);
  border: none;
  box-shadow: none;
}

.col-island-content switch:checked {
  background-color: @accent_bg_color;
}

.col-island-content switch slider {
  background-color: white;
  box-shadow: none;
  border: none;
}

.col-island-content scrollbar {
  background: none;
}

.col-island-content scrollbar slider {
  background-color: alpha(white, 0.25);
}
""";

    public void load (Gdk.Display display) {
        var provider = new Gtk.CssProvider ();
        provider.load_from_string (CSS);
        Gtk.StyleContext.add_provider_for_display (display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
}
