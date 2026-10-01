import AppKit
import QuartzCore

/// What lies behind the island, lightly blurred and dimmed: the Transparent glass of the open island.
///
/// Built on CABackdropLayer and CAFilter, the private Core Animation classes behind every blur on macOS, because
/// Liquid Glass has no setting clear enough to see the desktop through a panel this size. Looked up at run time:
/// without them `make` returns nil and the island uses Liquid Glass instead.
@MainActor
enum Backdrop {
    static func make(blur radius: Double, brightness: Double, saturation: Double) -> CALayer? {
        let create = NSSelectorFromString("filterWithType:")
        guard let layerType = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let filterType = NSClassFromString("CAFilter") as? NSObject.Type,
              filterType.responds(to: create)
        else { return nil }
        let layer = layerType.init()
        // Sample the windows and the desktop behind the island, not only the island's own window.
        guard layer.responds(to: NSSelectorFromString("setWindowServerAware:")) else { return nil }
        layer.setValue(true, forKey: "windowServerAware")
        // A blur this light hides a half-resolution sample, drawn at a quarter of the cost.
        if layer.responds(to: NSSelectorFromString("setScale:")) { layer.setValue(0.5, forKey: "scale") }

        func filter(_ type: String, _ key: String, _ value: Double) -> NSObject? {
            guard let filter = filterType.perform(create, with: type)?.takeUnretainedValue() as? NSObject else { return nil }
            filter.setValue(value, forKey: key)
            return filter
        }
        layer.filters = [
            filter("gaussianBlur", "inputRadius", radius),
            // Dimmed so white stays readable over a white window, and a little more vivid, as glass looks.
            filter("colorBrightness", "inputAmount", brightness),
            filter("colorSaturate", "inputAmount", saturation),
        ].compactMap { $0 }
        return layer
    }
}

/// Retunes Apple's Liquid Glass: the `glassBackground` filter behind `NSGlassEffectView` can bend what lies behind
/// the glass like a lens (its refraction), which macOS leaves off on large panels and hides under a frosted blur.
/// Only filters and inputs that exist are touched: if macOS renames them, the glass simply stays Apple's own.
@MainActor
enum LiquidGlassTuning {
    static func apply(_ values: [String: Double], to view: NSView) {
        guard let root = view.layer else { return }
        for layer in backdrops(in: root) {
            guard let filter = layer.filters?.compactMap({ $0 as? NSObject }).first(where: { name(of: $0) == "glassBackground" }),
                  let keys = filter.perform(NSSelectorFromString("inputKeys"))?.takeUnretainedValue() as? [String]
            else { continue }
            for (key, value) in values where keys.contains(key) {
                layer.setValue(value, forKeyPath: "filters.glassBackground.\(key)")
            }
        }
    }

    private static func name(of filter: NSObject) -> String? {
        filter.responds(to: NSSelectorFromString("name")) ? filter.value(forKey: "name") as? String : nil
    }

    private static func backdrops(in layer: CALayer) -> [CALayer] {
        let own = NSStringFromClass(type(of: layer)) == "CABackdropLayer" ? [layer] : []
        return own + (layer.sublayers ?? []).flatMap { backdrops(in: $0) }
    }
}

