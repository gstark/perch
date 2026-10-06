import CoreGraphics
import Foundation

/// Window management's lists as settings.json spells them, each record with its shortcut and alias.
enum WindowManagementFileFormat {
    /// Every command's chord or alias, nil for none; one of the wrong type has no entry and keeps its own.
    typealias CommandTexts = (texts: [WindowCommand.ID: String?], problems: [String])

    /// A list read back from the file: the records it could use, and what it had to skip.
    struct Decoded<Record> {
        var records: [Record] = []
        /// By record, nil for `null`; a field left out or of the wrong type has none, and keeps its value.
        var shortcuts: [UUID: String?] = [:]
        var aliases: [UUID: String?] = [:]
        var problems: [String] = []
    }

    // MARK: - Command shortcuts

    /// Every command, unbound ones as `null`, so the file itself lists what can be bound.
    static func json(commandShortcuts: [WindowCommand.ID: String]) -> SettingsFileJSON {
        .object(
            WindowCommand.ID.allCases.map { id in
                SettingsFileJSON.Member(key: id.rawValue, value: text(commandShortcuts[id]))
            })
    }

    /// A command the object leaves out is unbound, the same as one set to `null`.
    static func commandShortcuts(from json: SettingsFileJSON) -> CommandTexts? {
        commandTexts(from: json, noun: "a shortcut")
    }

    // MARK: - Command aliases

    static func json(commandAliases: [WindowCommand.ID: String]) -> SettingsFileJSON {
        .object(
            WindowCommand.ID.allCases.compactMap { id in
                commandAliases[id].map { SettingsFileJSON.Member(key: id.rawValue, value: .string($0)) }
            })
    }

    static func commandAliases(from json: SettingsFileJSON) -> CommandTexts? {
        commandTexts(from: json, noun: "an alias")
    }

    private static func commandTexts(from json: SettingsFileJSON, noun: String) -> CommandTexts? {
        guard let members = json.members else { return nil }
        var texts = Dictionary(uniqueKeysWithValues: WindowCommand.ID.allCases.map { ($0, String?.none) })
        var problems: [String] = []
        for member in members {
            guard let id = WindowCommand.ID(rawValue: member.key) else {
                problems.append("no command is called “\(member.key)”")
                continue
            }
            switch member.value {
            case .null: continue
            case .string(let text): texts[id] = text
            default:
                texts.removeValue(forKey: id)
                problems.append("“\(member.key)” needs \(noun) in quotes, or null")
            }
        }
        return (texts, problems)
    }

    // MARK: - Custom sizes

    static func json(_ size: CustomWindowSize, shortcut: String?, alias: String?) -> SettingsFileJSON {
        .object([
            "id": .string(size.id.uuidString.lowercased()),
            "name": .string(size.name),
            "width": .string(spelled(size.width)),
            "height": .string(spelled(size.height)),
            "position": .string(size.anchor.rawValue),
            "offset": offset(x: Double(size.offset.x), y: Double(size.offset.y)),
            "shortcut": text(shortcut),
            "alias": text(alias)
        ])
    }

    static func customSizes(from json: SettingsFileJSON) -> Decoded<CustomWindowSize>? {
        guard let items = json.items else { return nil }
        var decoded = Decoded<CustomWindowSize>()
        for (index, item) in items.enumerated() {
            guard let name = item["name"]?.string else {
                decoded.problems.append("custom size \(index + 1) needs a “name”")
                continue
            }
            let label = "custom size “\(name)”"
            guard let width = dimension(item["width"]), let height = dimension(item["height"]) else {
                decoded.problems.append("\(label) needs a “width” and “height”, as \"60%\" or \"900pt\"")
                continue
            }
            let id = identity(of: item, kind: "custom-size", name: name, label: label, into: &decoded)
            let offset = point(item["offset"], label: label, into: &decoded)
            decoded.records.append(
                CustomWindowSize(
                    id: id, name: name, width: width, height: height,
                    anchor: anchor(item["position"], label: label, into: &decoded),
                    offset: CustomWindowSize.Offset(
                        x: Int(exactly: offset.x.rounded()) ?? 0,
                        y: Int(exactly: offset.y.rounded()) ?? 0)))
            texts(of: item, id: id, label: label, into: &decoded)
        }
        return decoded
    }

    // MARK: - Fields

    private static func text(_ value: String?) -> SettingsFileJSON {
        value.map(SettingsFileJSON.string) ?? .null
    }

    private static func offset(x: Double, y: Double) -> SettingsFileJSON {
        .object(["x": .number(x), "y": .number(y)])
    }

    private static func spelled(_ dimension: CustomWindowSize.Dimension) -> String {
        "\(dimension.value)\(dimension.unit.suffix)"
    }

    /// `"60%"` or `"900pt"`; a bare number reads as points, the unit a person means by one.
    private static func dimension(_ json: SettingsFileJSON?) -> CustomWindowSize.Dimension? {
        if let points = json?.number {
            return Int(exactly: points.rounded()).map { .init($0, .points) }
        }
        guard let spelled = json?.string?.trimmingCharacters(in: .whitespaces).lowercased() else {
            return nil
        }
        for unit in CustomWindowSize.Dimension.Unit.allCases where spelled.hasSuffix(unit.suffix) {
            let number = spelled.dropLast(unit.suffix.count).trimmingCharacters(in: .whitespaces)
            return Double(number).flatMap { Int(exactly: $0.rounded()) }.map { .init($0, unit) }
        }
        return nil
    }

    /// The record's own id, or one its name always yields when the file was written without one.
    private static func identity<Record>(
        of item: SettingsFileJSON, kind: String, name: String, label: String,
        into decoded: inout Decoded<Record>
    ) -> UUID {
        let derived = SettingsFileIdentity.uuid(for: kind + ":" + name.lowercased())
        guard let spelled = item["id"] else { return derived }
        guard let id = spelled.string.flatMap(UUID.init(uuidString:)) else {
            decoded.problems.append("\(label): “id” isn't a UUID, so one was derived from the name")
            return derived
        }
        return id
    }

    private static func anchor<Record>(
        _ json: SettingsFileJSON?, label: String, into decoded: inout Decoded<Record>
    ) -> WindowLayoutAnchor {
        guard let spelled = json?.string else { return .center }
        guard let anchor = WindowLayoutAnchor(rawValue: spelled) else {
            decoded.problems.append("\(label): no position is called “\(spelled)”")
            return .center
        }
        return anchor
    }

    private static func point<Record>(
        _ json: SettingsFileJSON?, label: String, into decoded: inout Decoded<Record>
    ) -> (x: Double, y: Double) {
        guard let json else { return (0, 0) }
        guard let x = json["x"]?.number, let y = json["y"]?.number else {
            decoded.problems.append("\(label): “offset” needs numbers for “x” and “y”")
            return (0, 0)
        }
        return (x, y)
    }

    private static func texts<Record>(
        of item: SettingsFileJSON, id: UUID, label: String, into decoded: inout Decoded<Record>
    ) {
        let fields: KeyValuePairs<String, WritableKeyPath<Decoded<Record>, [UUID: String?]>> = [
            "shortcut": \.shortcuts, "alias": \.aliases
        ]
        for (field, texts) in fields {
            switch item[field] {
            case nil: continue
            case .null?: decoded[keyPath: texts].updateValue(nil, forKey: id)
            case .string(let text)?: decoded[keyPath: texts][id] = text
            default: decoded.problems.append("\(label): “\(field)” needs quotes, or null")
            }
        }
    }


}
