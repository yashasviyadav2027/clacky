import Foundation

enum SoundStyle: String, CaseIterable, Identifiable {
    case thocky = "Thocky", creamy = "Creamy", clacky = "Clacky", clicky = "Clicky", fun = "Fun"
    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .thocky: return "Deep, low-pitched and muted"
        case .creamy: return "Smooth, soft and buttery"
        case .clacky: return "Bright, sharp and higher-pitched"
        case .clicky: return "A loud click on every press"
        case .fun: return "Silly sounds just for fun"
        }
    }
}

struct PackInfo: Identifiable, Hashable {
    enum Source { case recorded, synthesized, fun, custom }

    let name: String
    let style: SoundStyle?
    let switchType: String
    let blurb: String
    let source: Source
    var id: String { name }

    /// Short legend printed on the pack's keycap icon.
    var keycapLabel: String {
        if name == FunSound.duck.rawValue { return "🦆" }
        let words = name.split(separator: " ")
        return words.count > 1 ? String(words.prefix(2).compactMap(\.first)) : String(name.prefix(1))
    }

    /// "Thocky · Tactile", "Fun", …
    var subtitle: String {
        guard let style, style.rawValue != switchType else { return switchType }
        return "\(style.rawValue) · \(switchType)"
    }
}

enum PackCatalog {
    private static let recorded: [(String, SoundStyle, String, String)] = [
        ("Holy Panda", .thocky, "Tactile", "Deep, rounded thock with a crisp bump — a fan favourite"),
        ("Gateron Black Ink", .thocky, "Linear", "Low-pitched, smooth and heavy"),
        ("Topre", .thocky, "Tactile", "Soft, muffled thock of rubber-dome Topre boards"),
        ("NovelKeys Cream", .creamy, "Linear", "Smooth and poppy with a creamy edge"),
        ("Alpaca", .creamy, "Linear", "Buttery and muted"),
        ("Turquoise Tealio", .creamy, "Linear", "Smooth, mid-pitched and clean"),
        ("Gateron Red Ink", .clacky, "Linear", "Bright and poppy"),
        ("Cherry MX Black", .clacky, "Linear", "Classic, slightly scratchy clack"),
        ("Cherry MX Brown", .clacky, "Tactile", "The classic office mechanical sound"),
        ("Cherry MX Blue", .clicky, "Clicky", "The classic click-clack"),
        ("Kailh Box Navy", .clicky, "Clicky", "Loud, heavy click bar"),
        ("SKCM Blue Alps", .clicky, "Clicky", "Vintage 80s Alps click"),
        ("IBM Buckling Spring", .clicky, "Clicky", "The legendary IBM Model M"),
    ]

    private static let synthesized: [String: (SoundStyle, String)] = [
        "Thocky": (.thocky, "Generated deep thock"),
        "Creamy": (.creamy, "Generated soft, smooth sound"),
        "Clacky": (.clacky, "Generated bright clack"),
        "Clicky": (.clicky, "Generated blue-switch click"),
    ]

    static func all(bundled: [String], custom: [String]) -> [PackInfo] {
        let available = Set(bundled)
        var packs = recorded.filter { available.contains($0.0) }.map {
            PackInfo(name: $0.0, style: $0.1, switchType: $0.2, blurb: $0.3, source: .recorded)
        }
        // Bundled folders without catalog metadata still show up.
        let known = Set(recorded.map(\.0))
        packs += bundled.filter { !known.contains($0) }.map {
            PackInfo(name: $0, style: nil, switchType: "Recorded", blurb: "", source: .recorded)
        }
        packs += Profile.builtIn.map { p in
            let meta = synthesized[p.name]
            return PackInfo(name: p.name, style: meta?.0, switchType: "Synthesized", blurb: meta?.1 ?? "", source: .synthesized)
        }
        packs += FunSound.allCases.map {
            PackInfo(name: $0.rawValue, style: .fun, switchType: "Fun", blurb: $0.blurb, source: .fun)
        }
        let builtInNames = Set(packs.map(\.name))
        packs += custom.filter { !builtInNames.contains($0) }.map { PackInfo(name: $0, style: nil, switchType: "My pack", blurb: "From your Packs folder", source: .custom) }
        return packs
    }
}
