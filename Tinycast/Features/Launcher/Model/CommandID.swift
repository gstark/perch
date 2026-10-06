import Foundation

/// Built-in launcher actions, surfaced alongside the user-authored ones.
enum CommandID: String, CaseIterable, Sendable {
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case pasteSequentially = "command:paste-sequentially"
    case searchEmoji = "command:search-emoji"
    case openCamera = "command:open-camera"
    case openInBrowser = "command:open-in-browser"
    case runShellCommand = "command:run-shell-command"
    case joinNextMeeting = "command:join-next-meeting"
    case mySchedule = "command:my-schedule"
    case createEvent = "command:create-event"
    case copyMeetingLink = "command:copy-meeting-link"
    case openInCalendar = "command:open-in-calendar"
    case createWindowLayout = "command:create-window-layout"
    case captureWindowLayout = "command:capture-window-layout"
    case switchRoom = "command:switch-room"
    case createRoom = "command:create-room"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case settings = "command:settings"
    case quit = "command:quit"

    var name: String {
        switch self {
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .pasteSequentially: return "Paste Sequentially"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .openCamera: return "Open Camera"
        case .openInBrowser: return "Open in Browser"
        case .runShellCommand: return "Run Shell Command"
        case .joinNextMeeting: return "Join Next Meeting"
        case .mySchedule: return "My Schedule"
        case .createEvent: return "Create Event"
        case .copyMeetingLink: return "Copy Meeting Link"
        case .openInCalendar: return "Open in Calendar"
        case .createWindowLayout: return "Create Window Layout"
        case .captureWindowLayout: return "Create Layout from Current Windows"
        case .switchRoom: return "Switch Room"
        case .createRoom: return "Create Room"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .settings: return "Perch Settings"
        case .quit: return "Quit Perch"
        }
    }

    var sfSymbol: String {
        switch self {
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pasteSequentially: return "list.bullet.clipboard"
        case .searchEmoji: return "face.smiling"
        case .openCamera: return "camera"
        case .openInBrowser: return "globe"
        case .runShellCommand: return "terminal"
        case .joinNextMeeting: return "video.fill"
        case .mySchedule: return "calendar"
        case .createEvent: return "calendar.badge.plus"
        case .copyMeetingLink: return "link"
        case .openInCalendar: return "calendar.badge.clock"
        case .createWindowLayout: return "plus.rectangle.on.rectangle"
        case .captureWindowLayout: return "macwindow.badge.plus"
        case .switchRoom: return "door.left.hand.open"
        case .createRoom: return "rectangle.stack.badge.plus"
        case .searchSnippets: return "curlybraces"
        case .createSnippet: return "plus.rectangle.on.rectangle"
        case .settings: return "gearshape"
        case .quit: return "power"
        }
    }


    /// Queries this command wins until the user opens a rival more.
    var boostedTerms: Set<String> { [] }

    /// Suggested, highest first, until the user's own habits fill the section.
    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .mySchedule: 60
        case .searchEmoji: 50
        case .createSnippet: 30
        default: nil
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser || self == .runShellCommand
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
