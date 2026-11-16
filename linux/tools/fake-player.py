#!/usr/bin/env python3
"""A silent MPRIS player, to work on the island's music without sound, and to check it end to end.

usage: fake-player.py [--zero-position] [--title T] [--artist A] [--album B] [--length SECONDS] [--art FILE]

It plays the track it is given, answers PlayPause, Next, Previous, Seek and SetPosition, and says so on the bus as a
real player would. With --zero-position it reports a position of 0 whatever it is, as some players do.
"""
import argparse
import time

from gi.repository import Gio, GLib

INTERFACES = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="Identity" type="s" access="read"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition"><arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/></method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

PATH = "/org/mpris/MediaPlayer2"


class Player:
    def __init__(self, args):
        self.args = args
        self.playing = True
        self.track = 1
        self.base = 0.0
        self.since = time.monotonic()
        self.connection = None

    def position(self):
        return self.base + ((time.monotonic() - self.since) if self.playing else 0.0)

    def metadata(self):
        data = {
            "mpris:trackid": GLib.Variant("o", f"/org/col/track/{self.track}"),
            "mpris:length": GLib.Variant("x", int(self.args.length * 1_000_000)),
            "xesam:title": GLib.Variant("s", self.args.title if self.track == 1 else f"{self.args.title} ({self.track})"),
            "xesam:artist": GLib.Variant("as", [self.args.artist]),
            "xesam:album": GLib.Variant("s", self.args.album),
        }
        if self.args.art:
            data["mpris:artUrl"] = GLib.Variant("s", "file://" + self.args.art)
        return data

    def get(self, interface, name):
        values = {
            "Identity": GLib.Variant("s", "Fake Player"),
            "CanQuit": GLib.Variant("b", False),
            "CanRaise": GLib.Variant("b", False),
            "HasTrackList": GLib.Variant("b", False),
            "SupportedUriSchemes": GLib.Variant("as", []),
            "SupportedMimeTypes": GLib.Variant("as", []),
            "PlaybackStatus": GLib.Variant("s", "Playing" if self.playing else "Paused"),
            "Rate": GLib.Variant("d", 1.0),
            "Metadata": GLib.Variant("a{sv}", self.metadata()),
            "Volume": GLib.Variant("d", 1.0),
            "Position": GLib.Variant("x", 0 if self.args.zero_position else int(self.position() * 1_000_000)),
            "MinimumRate": GLib.Variant("d", 1.0),
            "MaximumRate": GLib.Variant("d", 1.0),
        }
        return values.get(name, GLib.Variant("b", True))

    def changed(self, names):
        props = {name: self.get("org.mpris.MediaPlayer2.Player", name) for name in names}
        self.connection.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                    GLib.Variant("(sa{sv}as)", ("org.mpris.MediaPlayer2.Player", props, [])))

    def seeked(self):
        self.connection.emit_signal(None, PATH, "org.mpris.MediaPlayer2.Player", "Seeked",
                                    GLib.Variant("(x)", (int(self.position() * 1_000_000),)))

    def call(self, connection, sender, path, interface, method, params, invocation):
        if method in ("PlayPause", "Play", "Pause"):
            self.base = self.position()
            self.since = time.monotonic()
            self.playing = {"PlayPause": not self.playing, "Play": True, "Pause": False}[method]
            self.changed(["PlaybackStatus"])
        elif method in ("Next", "Previous"):
            self.track = max(1, self.track + (1 if method == "Next" else -1))
            self.base, self.since = 0.0, time.monotonic()
            self.changed(["Metadata"])
        elif method == "Seek":
            self.base, self.since = max(0.0, self.position() + params.unpack()[0] / 1_000_000), time.monotonic()
            self.seeked()
        elif method == "SetPosition":
            self.base, self.since = params.unpack()[1] / 1_000_000, time.monotonic()
            self.seeked()
        invocation.return_value(None)

    def get_property(self, connection, sender, path, interface, name):
        return self.get(interface, name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zero-position", action="store_true")
    parser.add_argument("--title", default="Bohemian Rhapsody")
    parser.add_argument("--artist", default="Queen")
    parser.add_argument("--album", default="A Night at the Opera")
    parser.add_argument("--length", type=float, default=354.0)
    parser.add_argument("--art", default="")
    parser.add_argument("--start", type=float, default=0.0, help="the position it starts at, in seconds")
    args = parser.parse_args()

    player = Player(args)
    player.base = args.start
    nodes = Gio.DBusNodeInfo.new_for_xml(INTERFACES)

    def acquired(connection, name):
        player.connection = connection
        for info in nodes.interfaces:
            connection.register_object(PATH, info, player.call, player.get_property, None)

    Gio.bus_own_name(Gio.BusType.SESSION, "org.mpris.MediaPlayer2.fakeplayer", Gio.BusNameOwnerFlags.NONE,
                     acquired, None, None)
    GLib.MainLoop().run()


if __name__ == "__main__":
    main()
