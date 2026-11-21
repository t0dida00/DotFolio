import DotFolioModels
import SwiftUI

extension ServiceType {
    /// SF Symbol for this service.
    var symbol: String {
        switch self {
        case .firebase: "flame"
        case .supabase: "bolt"
        case .stripe: "creditcard"
        case .aws: "cloud"
        case .googleCloud: "cloud.sun"
        case .googleMaps: "map"
        case .vercel: "triangle"
        case .custom: "square.stack.3d.up"
        }
    }

    /// Symbol for any service name, custom ones included.
    /// A provider's icon: its own for the 8 known ones, otherwise the icon of
    /// what it's for (Hugging Face → AI ✨), else the generic one.
    static func symbol(for name: String) -> String {
        if let known = ServiceType(matching: name) { return known.symbol }
        return ServiceCategory.suggested(forProvider: name)?.symbol ?? ServiceType.custom.symbol
    }

    /// Hue for a provider's icon tile.
    var tint: Color {
        switch self {
        case .firebase: DS.Palette.orange
        case .supabase: DS.Palette.aqua
        case .stripe: DS.Palette.violet
        case .aws: DS.Palette.yellow
        case .googleCloud: DS.Palette.blue
        case .googleMaps: DS.Palette.green
        case .vercel: DS.Palette.neutral
        case .custom: DS.Palette.magenta
        }
    }

    /// Same rule as `symbol(for:)` for the hue.
    static func tint(for name: String) -> Color {
        if let known = ServiceType(matching: name) { return known.tint }
        return ServiceCategory.suggested(forProvider: name)?.tint ?? ServiceType.custom.tint
    }
}

extension ServiceCategory {
    var symbol: String {
        switch self {
        case .database: "cylinder.split.1x2"
        case .cache: "bolt.horizontal"
        case .storage: "externaldrive"
        case .auth: "person.badge.key"
        case .payments: "creditcard"
        case .email: "envelope"
        case .analytics: "chart.bar"
        case .monitoring: "waveform.path.ecg"
        case .hosting: "server.rack"
        case .maps: "map"
        case .search: "magnifyingglass"
        case .queue: "tray.2"
        case .ai: "sparkles"
        case .messaging: "message"
        case .cms: "doc.richtext"
        case .flags: "flag"
        case .dataAPI: "globe"
        case .other: "square.dashed"
        }
    }

    static func symbol(for name: String) -> String {
        (ServiceCategory(matching: name) ?? .other).symbol
    }

    /// Grouped hues (existing palette only): data & content → blue, money →
    /// green, identity & AI → violet, comms → magenta, observability & flags →
    /// orange, infrastructure, maps & data APIs → aqua.
    var tint: Color {
        switch self {
        case .database, .cache, .storage, .search, .queue: DS.Palette.blue
        case .payments: DS.Palette.green
        case .auth, .ai: DS.Palette.violet
        case .email, .messaging: DS.Palette.magenta
        case .analytics, .monitoring, .flags: DS.Palette.orange
        case .hosting, .maps, .dataAPI: DS.Palette.aqua
        case .cms: DS.Palette.blue
        case .other: DS.Palette.neutral
        }
    }

    static func tint(for name: String) -> Color {
        (ServiceCategory(matching: name) ?? .other).tint
    }
}
