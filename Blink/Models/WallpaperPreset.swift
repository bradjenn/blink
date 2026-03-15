import Foundation

struct WallpaperPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let filename: String
}

extension WallpaperPreset {
    static let all: [WallpaperPreset] = [
        WallpaperPreset(id: "preset:ship-at-sea", name: "Ship at Sea", filename: "ship-at-sea.jpg"),
        WallpaperPreset(id: "preset:akane-pagoda", name: "Akane Pagoda", filename: "akane-pagoda.jpg"),
        WallpaperPreset(id: "preset:everforest", name: "Everforest", filename: "everforest.jpg"),
        WallpaperPreset(id: "preset:gruvbox-ferns", name: "Gruvbox Ferns", filename: "gruvbox-ferns.jpg"),
        WallpaperPreset(id: "preset:akane-cliff", name: "Akane Cliff", filename: "akane-cliff.jpg"),
        WallpaperPreset(id: "preset:akane-bridge", name: "Akane Bridge", filename: "akane-bridge.jpg"),
        WallpaperPreset(id: "preset:akane-mist", name: "Akane Mist", filename: "akane-mist.jpg"),
        WallpaperPreset(id: "preset:pink-lakeside", name: "Pink Lakeside", filename: "pink-lakeside.png"),
    ]

    static func find(_ id: String) -> WallpaperPreset? {
        all.first { $0.id == id }
    }
}
