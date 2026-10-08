import Foundation

/// App actions the Inbox can trigger that the core can't perform on its own.
public protocol FocusActions: AnyObject {
    /// Show a "Start N min on X?" card. Returns false if it can't be shown right now.
    func suggestFocus(task: TaskItem, minutes: Int, why: String?) -> Bool
    /// Start the timer. Returns an error message, or nil on success.
    func startFocus(task: TaskItem, minutes: Int) -> String?
}

public enum InboxCommand: Equatable {
    case create(TaskItem)
    case reschedule(id: String, day: String)
    case priority(id: String, Priority)
    case estimate(id: String, sessions: Int)
    case complete(id: String)
    case reopen(id: String)
    case cancel(id: String)
    case later(id: String)
    case suggestFocus(id: String, minutes: Int)
    case startFocus(id: String, minutes: Int)
    case linkSession(sessionId: String, taskId: String)
}

/// Reads unchecked lines in `PastelFocus/Inbox.md`, applies them, and ticks each with its result:
/// `- [x] complete 🆔 e1w5 → applied 10:02 by hermes` or `→ error: …`.
public final class InboxProcessor {
    let store: TaskStore
    let calendar: DayCalendar
    let clock: Clock
    public weak var actions: FocusActions?

    public init(store: TaskStore, calendar: DayCalendar, clock: Clock) {
        self.store = store
        self.calendar = calendar
        self.clock = clock
    }

    public static let header = [
        "# PastelFocus Inbox", "",
        "Hermes (or you) can add one command per line as `- [ ] <command>`. PastelFocus applies it within a second and ticks it with the result.", "",
        "Commands: `create <task line>` · `reschedule 🆔 id ⏳ YYYY-MM-DD` · `priority 🆔 id urgent|high|medium|low|none` · `estimate 🆔 id N` · `complete 🆔 id` · `reopen 🆔 id` · `cancel 🆔 id` · `later 🆔 id` · `suggest-focus 🆔 id 40m` · `start-focus 🆔 id 25m` · `link-session <session id> 🆔 id`. Add ` — reason: …` or ` — why: …` to explain.", "",
        "## Commands", "",
    ]

    public struct Parsed: Equatable {
        public var command: InboxCommand
        public var actor: Actor
        public var reason: String?
    }

    public static func parse(_ text: String) throws -> Parsed {
        var body = text.trimmingCharacters(in: .whitespaces)
        var actor: Actor = .hermes
        if body.contains("#by-you") { actor = .you; body = body.replacingOccurrences(of: "#by-you", with: "") }
        var reason: String?
        if let r = body.range(of: " — ") {
            let tail = body[r.upperBound...].trimmingCharacters(in: .whitespaces)
            for key in ["reason:", "why:"] where tail.lowercased().hasPrefix(key) {
                reason = String(tail.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
                body = String(body[..<r.lowerBound])
            }
        }
        let verb = body.split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        let rest = String(body.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        let id = Self.match(#"🆔\s*([A-Za-z0-9_-]+)"#, in: rest)
        func needID() throws -> String { guard let id else { throw InboxError("missing 🆔 task id") }; return id }
        func minutes() -> Int { Self.match(#"(\d+)\s*m(?:in)?\b"#, in: rest).flatMap(Int.init) ?? 25 }

        let cmd: InboxCommand
        switch verb {
        case "create":
            guard var t = TaskLineParser.parse("- [ ] " + rest), !t.description.isEmpty else { throw InboxError("nothing to create") }
            t.taskID = nil
            cmd = .create(t)
        case "reschedule":
            guard let day = Self.match(#"(\d{4}-\d{2}-\d{2})"#, in: rest) else { throw InboxError("missing ⏳ YYYY-MM-DD") }
            cmd = .reschedule(id: try needID(), day: day)
        case "priority":
            let p: Priority
            if rest.contains("🔺") || rest.lowercased().contains("urgent") { p = .urgent }
            else if rest.contains("⏫") || rest.lowercased().contains("high") { p = .high }
            else if rest.contains("🔼") || rest.lowercased().contains("medium") { p = .medium }
            else if rest.contains("🔽") || rest.lowercased().contains("low") { p = .low }
            else if rest.lowercased().contains("none") { p = .none }
            else { throw InboxError("missing priority (urgent, high, medium, low or none)") }
            cmd = .priority(id: try needID(), p)
        case "estimate":
            let stripped = rest.replacingOccurrences(of: #"🆔\s*[A-Za-z0-9_-]+"#, with: "", options: .regularExpression)
            guard let n = Self.match(#"(\d+)"#, in: stripped).flatMap(Int.init) else { throw InboxError("missing number of sessions") }
            cmd = .estimate(id: try needID(), sessions: n)
        case "complete", "done": cmd = .complete(id: try needID())
        case "reopen": cmd = .reopen(id: try needID())
        case "cancel": cmd = .cancel(id: try needID())
        case "later": cmd = .later(id: try needID())
        case "suggest-focus": cmd = .suggestFocus(id: try needID(), minutes: minutes())
        case "start-focus": cmd = .startFocus(id: try needID(), minutes: minutes())
        case "link-session":
            guard let sid = Self.match(#"\b(s[a-z0-9]{7})\b"#, in: rest) else { throw InboxError("missing session id") }
            cmd = .linkSession(sessionId: sid, taskId: try needID())
        default:
            throw InboxError("unknown command \"\(verb)\"")
        }
        return Parsed(command: cmd, actor: actor, reason: reason)
    }

    public struct InboxError: Error, CustomStringConvertible {
        public let description: String
        init(_ d: String) { description = d }
    }

    /// Applies every pending command. Returns how many lines were processed.
    @discardableResult
    public func process() throws -> Int {
        let url = store.config.inbox
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try SafeFile.edit(url) { lines in lines = Self.header }
            return 0
        }
        let pending = SafeFile.readLines(url).enumerated().compactMap { (i, line) -> (Int, String)? in
            guard let t = TaskLineParser.parse(line), t.status == .todo else { return nil }
            let raw = line.trimmingCharacters(in: .whitespaces)
            return (i, String(raw.dropFirst(6)))
        }
        guard !pending.isEmpty else { return 0 }

        var results: [String: String] = [:]
        for (_, text) in pending { results[text] = apply(text) }
        try SafeFile.edit(url) { lines in
            for (i, line) in lines.enumerated() {
                guard let t = TaskLineParser.parse(line), t.status == .todo else { continue }
                let text = String(line.trimmingCharacters(in: .whitespaces).dropFirst(6))
                if let result = results[text] { lines[i] = "- [x] \(text) → \(result)" }
            }
        }
        return pending.count
    }

    func apply(_ text: String) -> String {
        let time = calendar.timeString(clock.now())
        do {
            let p = try Self.parse(text)
            let who = p.actor.rawValue
            switch p.command {
            case .create(let t):
                let made = try store.create(t, actor: p.actor, reason: p.reason)
                return "created 🆔 \(made.taskID!) \(time) by \(who)"
            case .reschedule(let id, let day): try store.reschedule(id, to: day, actor: p.actor, reason: p.reason)
            case .priority(let id, let pr): try store.setPriority(id, pr, actor: p.actor)
            case .estimate(let id, let n): try store.setEstimate(id, sessions: n, actor: p.actor)
            case .complete(let id): try store.setStatus(id, .done, actor: p.actor, reason: p.reason)
            case .reopen(let id): try store.setStatus(id, .todo, actor: p.actor, reason: p.reason)
            case .cancel(let id): try store.setStatus(id, .cancelled, actor: p.actor, reason: p.reason)
            case .later(let id): try store.addTag(id, "later", actor: p.actor)
            case .suggestFocus(let id, let minutes):
                guard let t = store.find(id) else { throw InboxError("no task 🆔 \(id)") }
                guard let actions, actions.suggestFocus(task: t, minutes: minutes, why: p.reason) else {
                    throw InboxError("app couldn't show the suggestion")
                }
                return "suggested \(time)"
            case .startFocus(let id, let minutes):
                guard let t = store.find(id) else { throw InboxError("no task 🆔 \(id)") }
                guard let actions else { throw InboxError("app not running") }
                if let err = actions.startFocus(task: t, minutes: minutes) { throw InboxError(err) }
                return "started \(time)"
            case .linkSession(let sid, let id):
                guard store.find(id) != nil else { throw InboxError("no task 🆔 \(id)") }
                try store.events.append(TaskEvent(at: clock.now(), taskId: id, type: .sessionLinked, new: sid, actor: p.actor, reason: p.reason), at: clock.now())
            }
            return "applied \(time) by \(who)"
        } catch {
            return "error: \(error)"
        }
    }

    static func match(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
