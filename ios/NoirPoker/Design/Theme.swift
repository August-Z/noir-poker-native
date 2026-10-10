import SwiftUI

extension Color {
    /// Builds a color from CSS hex: `#rrggbb` or `#rrggbbaa` (alpha last, as in CSS).
    init(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        let value = UInt64(text, radix: 16) ?? 0
        let r, g, b, a: Double
        if text.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// The NOIR palette (reference `:root` tokens and semantic families). Dark only.
enum Noir {
    // Root tokens.
    static let bg = Color(hex: "#0b1017")
    static let panel = Color(hex: "#111923")
    static let line = Color(hex: "#25313d")
    static let muted = Color(hex: "#8897a6")
    static let text = Color(hex: "#edf3f6")
    static let mint = Color(hex: "#6ee7c5")
    static let mintDark = Color(hex: "#153d36")
    static let purple = Color(hex: "#b4a2ff")
    static let red = Color(hex: "#e56f80")
    static let felt = Color(hex: "#14362f")

    // Header and chrome.
    static let headerBorder = Color(hex: "#202b35")
    static let brandLight = Color(hex: "#a1b1be")
    static let headerCenter = Color(hex: "#a7b6c3")
    static let eyebrow = Color(hex: "#7f9b9c")
    static let surfaceBorder = Color(hex: "#28353f")
    static let surfaceTopText = Color(hex: "#9cb0bf")
    static let sidebarBorder = Color(hex: "#27333d")
    static let coachBorder = Color(hex: "#33584f")
    static let dialogBg = Color(hex: "#14202a")
    static let dialogBorder = Color(hex: "#3b504f")
    static let dialogBody = Color(hex: "#a8bdc7")
    static let selectBg = Color(hex: "#1b2632")
    static let selectText = Color(hex: "#d2dbe3")
    static let selectBorder = Color(hex: "#34404a")
    static let stripDivider = Color(hex: "#253039")
    static let statsDivider = Color(hex: "#2a3540")
    static let stripText = Color(hex: "#a7b8c4")
    static let sliderLabel = Color(hex: "#8093a3")
    static let footer = Color(hex: "#8a9dad") // #697d8c nudged lighter for contrast
    static let footerButton = Color(hex: "#8fa0ae")
    static let subtle = Color(hex: "#7c909f")
    static let note = Color(hex: "#e3c588")

    // Felt and rail.
    static let railStops = [Color(hex: "#31434c"), Color(hex: "#16232d"), Color(hex: "#31464b")]
    static let railBorder = Color(hex: "#425860")
    static let feltCenter = Color(hex: "#16433e")
    static let feltEdge = Color(hex: "#102e2b")
    static let feltBorder = Color(hex: "#438b7955")
    static let feltOutline = Color(hex: "#6ee7c522")
    static let watermark = Color(hex: "#76b8a522")
    static let slotBorder = Color(hex: "#73a99830")
    static let slotFill = Color(hex: "#0e262420")
    static let slotGlyph = Color(hex: "#81b9a420")
    static let potTrigger = Color(hex: "#9fbbb1")
    static let boardCaption = Color(hex: "#89a99c")

    // Seats.
    static let plate = Color(hex: "#131e29")
    static let plateBorder = Color(hex: "#3b4b5a")
    static let plateFoldedBorder = Color(hex: "#394449")
    static let plateFolded = Color(hex: "#101923")
    static let styleChipBorder = Color(hex: "#62988b")
    static let styleChipBg = Color(hex: "#1b3d35")
    static let styleChipText = Color(hex: "#cff0e4")
    static let seatStack = Color(hex: "#89a4b0")
    static let seatAction = Color(hex: "#91abae")
    static let seatAmount = Color(hex: "#c8ddd3")
    static let peekBorder = Color(hex: "#527266")
    static let peekPressedBg = Color(hex: "#24483e")
    static let peekPressedBorder = Color(hex: "#70b49b")
    static let heroStack = Color(hex: "#99baae")
    static let heroAvatarBg = Color(hex: "#18372f")

    static let avatarFills: [(bg: Color, fg: Color)] = [
        (Color(hex: "#394d69"), Color(hex: "#c9e1ff")),
        (Color(hex: "#755845"), Color(hex: "#ffddbe")),
        (Color(hex: "#3e625e"), Color(hex: "#b8efe2")),
        (Color(hex: "#685261"), Color(hex: "#f1d0e3")),
        (Color(hex: "#564968"), Color(hex: "#e0d0f8")),
    ]
    static func avatar(_ seat: Int) -> (bg: Color, fg: Color) { avatarFills[min(max(seat - 1, 0), avatarFills.count - 1)] }

    // Position badges.
    static let badgeBg = Color(hex: "#273642")
    static let badgeText = Color(hex: "#b3c5cf")
    static let btnBg = Color(hex: "#e3e9df")
    static let btnText = Color(hex: "#26322e")
    static let sbBg = Color(hex: "#265149")
    static let sbText = Color(hex: "#9ee3ca")
    static let bbBg = Color(hex: "#354a63")
    static let bbText = Color(hex: "#c5ddf5")

    // Rank badges and winners.
    static let rankBg = Color(hex: "#23483f")
    static let rankText = Color(hex: "#c6f1df")
    static let rankBorder = Color(hex: "#5cbfa35c")
    static let winBg = Color(hex: "#483e26")
    static let winText = Color(hex: "#ffe0a0")
    static let gold = Color(hex: "#e3bf72")
    static let goldSeat = Color(hex: "#d2b36b")
    static let goldAction = Color(hex: "#e6d3a2")
    static let goldLight = Color(hex: "#f4d99e")
    static let goldWon = Color(hex: "#ebd097")
    static let goldMuted = Color(hex: "#b7a57d")
    static let goldBorder = Color(hex: "#8b794a")
    static let replayBorder = Color(hex: "#82724d")
    static let replayText = Color(hex: "#e5ce98")
    static let replayBg = Color(hex: "#332d1f66")

    // Moods.
    static func moodRing(_ mood: String) -> Color? {
        switch mood {
        case "frustrated", "reactive": return Color(hex: "#d89568")
        case "cautious": return Color(hex: "#a2b4d9")
        case "confident": return Color(hex: "#e1c173")
        default: return nil
        }
    }

    // Buttons.
    static let primaryText = Color(hex: "#0c3026")
    static let raiseText = Color(hex: "#092a22")
    static let callBg = Color(hex: "#24383e")
    static let callText = Color(hex: "#c6e3dc")
    static let callBorder = Color(hex: "#48635f")
    static let foldBg = Color(hex: "#222b36")
    static let foldText = Color(hex: "#b1bdc9")
    static let foldBorder = Color(hex: "#38414d")
    static let presetBg = Color(hex: "#18222d")
    static let presetBorder = Color(hex: "#2b3945")
    static let finishBg = Color(hex: "#183f36")
    static let finishBorder = Color(hex: "#648c7f")
    static let finishText = Color(hex: "#bcf2dd")
    static let reviewBorder = Color(hex: "#736088")
    static let reviewBg = Color(hex: "#49365866")
    static let reviewText = Color(hex: "#ddcafa")

    // Session and activity.
    static let negative = Color(hex: "#dd8993")
    static let logHero = Color(hex: "#8ddbbe")
    static let logResult = Color(hex: "#e2cd8e")
    static let logStreet = Color(hex: "#cfdee2")
    static let logDefault = Color(hex: "#8ea3b2")

    // Showdown.
    static let showdownBorder = Color(hex: "#445344")
    static let showdownBg = Color(hex: "#101b22")
    static let scenePanel = Color(hex: "#12232a")
    static let scenePanelBorder = Color(hex: "#2c4342")
    static let sceneName = Color(hex: "#e0eae7")
    static let sceneHand = Color(hex: "#c4dbd1")
    static let sceneNoPot = Color(hex: "#8fa9a6")
    static let sceneMatch = Color(hex: "#dfc285")
    static let sceneMatchLoser = Color(hex: "#77b6a6")

    // Cards.
    static let cardInk = Color(hex: "#223447")
    static let cardRed = Color(hex: "#c74760")
    static let cardFace = [Color(hex: "#fffdf8"), Color(hex: "#f3f5f0"), Color(hex: "#e5eeec")]
    static let cardBorder = Color(hex: "#edf6f3")
    static let cardBackBase = Color(hex: "#1b3947")
    static let cardBackLineA = Color(hex: "#568c9540")
    static let cardBackLineB = Color(hex: "#60939850")
    static let cardBackBorder = Color(hex: "#7da8ad")
}

/// Shared gradients and surfaces.
enum NoirSurface {
    static let game = RadialGradient(
        colors: [Color(hex: "#12242c"), Color(hex: "#111c25"), Color(hex: "#101720")],
        center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 700)
    static let sidebar = LinearGradient(colors: [Color(hex: "#17202a88"), Color(hex: "#11182188")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let coach = LinearGradient(colors: [Color(hex: "#142e2966"), Color(hex: "#14212866")],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
}
