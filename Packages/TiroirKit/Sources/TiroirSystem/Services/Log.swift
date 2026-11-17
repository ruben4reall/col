import os

/// The system log, under the subsystem `ch.rubencatalao.tiroir`. Numbers, states and bundle identifiers only:
/// never a window title, an icon's label or a path.
public enum Log {
    public static let subsystem = "ch.rubencatalao.tiroir"
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let accessibility = Logger(subsystem: subsystem, category: "accessibility")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
