import AppIntents
import IsletPrompter
import IsletShell

/// Shortcuts actions: the same things the `islet` command does, without a terminal.
struct ShowActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Show in the Notch"
    static let description = IntentDescription("Shows a live activity beside the camera, or updates the one with the same name.")

    @Parameter(title: "Title") var title: String
    @Parameter(title: "Symbol", description: "An SF Symbol name, such as hammer.fill.") var symbol: String?
    @Parameter(title: "Progress", description: "From 0 to 1.", inclusiveRange: (0, 1)) var progress: Double?
    @Parameter(title: "Text") var text: String?
    @Parameter(title: "Colour", description: "A colour name, such as orange, or a hex value.") var tint: String?
    @Parameter(title: "Seconds on screen") var seconds: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$title) in the notch") {
            \.$symbol
            \.$progress
            \.$text
            \.$tint
            \.$seconds
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IslandController.shared?.push(
            id: Self.identifier(for: title), title: title, symbol: symbol, tint: tint,
            progress: progress, text: text, seconds: seconds.map(Double.init)
        )
        return .result()
    }

    static func identifier(for title: String) -> String {
        let slug = title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return "shortcut-" + String(slug.prefix(40))
    }
}

struct EndActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "End Notch Activity"
    static let description = IntentDescription("Marks an activity done: a check mark, then it leaves.")

    @Parameter(title: "Title") var title: String

    static var parameterSummary: some ParameterSummary {
        Summary("End \(\.$title) in the notch")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IslandController.shared?.finish(id: ShowActivityIntent.identifier(for: title))
        return .result()
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Notch Timer"
    static let description = IntentDescription("Starts a countdown that lives in the notch.")

    @Parameter(title: "Minutes", default: 5, inclusiveRange: (1, 1440)) var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer in the notch")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        IslandController.shared?.startTimer(minutes: minutes)
        return .result()
    }
}

struct OpenIslandIntent: AppIntent {
    static let title: LocalizedStringResource = "Open the Island"

    @MainActor
    func perform() async throws -> some IntentResult {
        IslandController.shared?.openIsland()
        return .result()
    }
}

struct PromptTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Prompt Text"
    static let description = IntentDescription("Rolls a text out of the notch in the prompter.")

    @Parameter(title: "Text") var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PrompterCenter.shared.prompt(text: text)
        return .result()
    }
}

struct PromptSelectedIntent: AppIntent {
    static let title: LocalizedStringResource = "Prompt the Selected Script"
    static let description = IntentDescription("Rolls the script selected in the prompter's library.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PrompterCenter.shared.promptSelected()
        return .result()
    }
}

struct TogglePrompterIntent: AppIntent {
    static let title: LocalizedStringResource = "Play or Pause the Prompter"

    @MainActor
    func perform() async throws -> some IntentResult {
        PrompterCenter.shared.playPause()
        return .result()
    }
}

struct ClosePrompterIntent: AppIntent {
    static let title: LocalizedStringResource = "Close the Prompter"

    @MainActor
    func perform() async throws -> some IntentResult {
        PrompterCenter.shared.prompter.stop()
        return .result()
    }
}

struct IsletShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTimerIntent(), phrases: ["Start a timer in \(.applicationName)"], shortTitle: "Timer", systemImageName: "timer")
        AppShortcut(intent: OpenIslandIntent(), phrases: ["Open \(.applicationName)"], shortTitle: "Open the Island", systemImageName: "rectangle.topthird.inset.filled")
        AppShortcut(intent: PromptSelectedIntent(), phrases: ["Start the prompter in \(.applicationName)"], shortTitle: "Prompter", systemImageName: "text.aligncenter")
    }
}
