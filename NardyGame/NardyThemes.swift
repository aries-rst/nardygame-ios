import SwiftUI

extension Color {
    /// ARGB hex literal, same encoding as Android's `0xAARRGGBB.toInt()`.
    init(hex: UInt32) {
        let a = Double((hex >> 24) & 0xFF) / 255.0
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// App chrome colors per theme — 1:1 port of Android's `UiPal`.
struct NUiPal {
    var bg: Color
    var bg2: Color
    var panel: Color
    var text: Color
    var muted: Color
    var accent: Color
    var accent2: Color
    var danger: Color
    var onAccent: Color = Color(hex: 0xFF1D140A)
}

/// Board colors — 1:1 port of Android's `BoardPal`. `ornStyle` names the
/// motif painted on each half (star/suzani/tulip/meander/medallion/khokhloma/
/// dragon/arabesque/knot/islimi/rhombus/rosette/starMed/none); `pointStyle`
/// (Kotlin: `points`) is tri/inlay/outlined/arrow.
struct NBoardPal {
    var frame: Color
    var frameIn: Color = Color(hex: 0xFF000000)
    var felt: Color
    var ptA: Color
    var ptB: Color
    var grain: Double = 0.9
    var orn: Color = .clear
    var ornAlpha: Double = 1
    var w1: Color = Color(hex: 0xFFFFFDF6)
    var w2: Color = Color(hex: 0xFFEFE3C8)
    var w3: Color = Color(hex: 0xFFBBA57A)
    var b1: Color = Color(hex: 0xFF5A4A40)
    var b2: Color = Color(hex: 0xFF241A14)
    var b3: Color = Color(hex: 0xFF090605)
    var hl: Color = Color(hex: 0xFF3FBF5A)
    var sel: Color = Color(hex: 0xFFFFCF33)
    var hinge: Color = Color(hex: 0xFFC9A24A)
    var ornStyle: String = "star"
    var pointStyle: String = "tri"
    var burn: Color = Color(hex: 0xFF3A1E0C)
    var inlay: Color = Color(hex: 0xFFC9A34A)
    /// Grain strength on the playing field; < 0 means "grain * 0.6" (see `effFeltGrain`).
    var feltGrain: Double = -1
    var stitch: Color? = nil
    var rim: Color? = nil
    var feltBorder: Color? = nil
    var khatam: Bool = false
    var ring: Color? = nil
    var mirrorDecor: Bool = false
    var trayA: Double = 0.55

    var effFeltGrain: Double { feltGrain < 0 ? grain * 0.6 : feltGrain }
}

/// 1:1 port of Android's `Theme.kt` — 20 board skins (chrome palette +
/// board felt/frame/point/ornament colors). Values are the exact hex
/// constants from the Kotlin source so the two platforms render the same
/// palette, even though the drawing code itself (`NardyOrnaments`,
/// `NardyBoardRenderer`) is a separate SwiftUI Canvas port.
enum NardyThemes {
    static let ids = [
        "wood", "beech", "walnut", "dragon", "pyro", "leather", "knot", "mahogany", "ebony", "tournament", "khatam", "carve",
        "samarkand", "suzani", "iznik", "aegean", "carpet", "khokhloma", "oriental", "dark"
    ]

    static func displayName(_ id: String) -> String {
        switch id {
        case "wood": return t("Wood", "Дерево")
        case "beech": return t("Beech", "Бук")
        case "walnut": return t("Walnut", "Орех")
        case "dragon": return t("Dragon", "Дракон")
        case "pyro": return t("Pyrography", "Выжигание")
        case "leather": return t("Leather", "Кожа")
        case "knot": return t("Knotwork", "Плетёнка")
        case "mahogany": return t("Mahogany", "Красное дерево")
        case "ebony": return t("Ebony & Gold", "Чёрное дерево")
        case "tournament": return t("Tournament", "Турнирная")
        case "khatam": return t("Khatam", "Хатам")
        case "carve": return t("Carved Islimi", "Резьба")
        case "samarkand": return t("Samarkand Majolica", "Самарканд")
        case "suzani": return t("Suzani", "Сюзане")
        case "iznik": return t("Iznik Tiles", "Изник")
        case "aegean": return t("Aegean", "Эгейская")
        case "carpet": return t("Caucasian Carpet", "Ковёр")
        case "khokhloma": return t("Khokhloma", "Хохлома")
        case "oriental": return t("Oriental", "Восточная")
        case "dark": return t("Dark", "Тёмная")
        default: return id
        }
    }

    private static let HL: UInt32 = 0xFF7EE08A
    private static let SEL: UInt32 = 0xFFFFD75E

    static func ui(_ theme: String) -> NUiPal {
        switch theme {
        case "oriental":
            return NUiPal(bg: Color(hex: 0xFF0B2A2E), bg2: Color(hex: 0xFF123D42), panel: Color(hex: 0xFF0F3438), text: Color(hex: 0xFFF4EAD2), muted: Color(hex: 0xFFB9C9C4), accent: Color(hex: 0xFFE0B04F), accent2: Color(hex: 0xFF2FA39A), danger: Color(hex: 0xFFD0644A))
        case "dark":
            return NUiPal(bg: Color(hex: 0xFF0D1017), bg2: Color(hex: 0xFF161B26), panel: Color(hex: 0xFF141924), text: Color(hex: 0xFFE8ECF4), muted: Color(hex: 0xFF9AA4B8), accent: Color(hex: 0xFF8FB4FF), accent2: Color(hex: 0xFF5B6F9A), danger: Color(hex: 0xFFE06A5A))
        case "samarkand":
            return NUiPal(bg: Color(hex: 0xFF0A1F3A), bg2: Color(hex: 0xFF13305A), panel: Color(hex: 0xFF0F2848), text: Color(hex: 0xFFF2ECDC), muted: Color(hex: 0xFFA9BDD6), accent: Color(hex: 0xFFE3B04B), accent2: Color(hex: 0xFF2FA3B5), danger: Color(hex: 0xFFE0644A))
        case "suzani":
            return NUiPal(bg: Color(hex: 0xFF3A1018), bg2: Color(hex: 0xFF521A24), panel: Color(hex: 0xFF461520), text: Color(hex: 0xFFFBEEE0), muted: Color(hex: 0xFFE0BFB0), accent: Color(hex: 0xFFE8B24A), accent2: Color(hex: 0xFF6F8A3A), danger: Color(hex: 0xFFFF8A6A))
        case "iznik":
            return NUiPal(bg: Color(hex: 0xFF0D2A4F), bg2: Color(hex: 0xFF163A66), panel: Color(hex: 0xFF12325A), text: Color(hex: 0xFFFDF8EF), muted: Color(hex: 0xFFB7C7DC), accent: Color(hex: 0xFFE7C35A), accent2: Color(hex: 0xFF2AA198), danger: Color(hex: 0xFFFF7A66))
        case "aegean":
            return NUiPal(bg: Color(hex: 0xFF0B2540), bg2: Color(hex: 0xFF123459), panel: Color(hex: 0xFF0F2D4D), text: Color(hex: 0xFFF5F8FC), muted: Color(hex: 0xFFA9C0D8), accent: Color(hex: 0xFF6CB4EA), accent2: Color(hex: 0xFF2E6DB4), danger: Color(hex: 0xFFFF7A66))
        case "carpet":
            return NUiPal(bg: Color(hex: 0xFF2B0D0D), bg2: Color(hex: 0xFF421616), panel: Color(hex: 0xFF381212), text: Color(hex: 0xFFF6E9D6), muted: Color(hex: 0xFFD8B9A0), accent: Color(hex: 0xFFE0A63C), accent2: Color(hex: 0xFF2F5A8A), danger: Color(hex: 0xFFFF8A6A))
        case "ebony":
            return NUiPal(bg: Color(hex: 0xFF0E0C0B), bg2: Color(hex: 0xFF1E1A16), panel: Color(hex: 0xFF171410), text: Color(hex: 0xFFF3EAD6), muted: Color(hex: 0xFFB9AB8A), accent: Color(hex: 0xFFC9A34A), accent2: Color(hex: 0xFF8A6E2E), danger: Color(hex: 0xFFE06A5A))
        case "tournament":
            return NUiPal(bg: Color(hex: 0xFF0F2A1C), bg2: Color(hex: 0xFF174029), panel: Color(hex: 0xFF133522), text: Color(hex: 0xFFF1EFE6), muted: Color(hex: 0xFFB6C9BB), accent: Color(hex: 0xFFE0B04F), accent2: Color(hex: 0xFFB3271C), danger: Color(hex: 0xFFFF7A66))
        case "khokhloma":
            return NUiPal(bg: Color(hex: 0xFF120B08), bg2: Color(hex: 0xFF241510), panel: Color(hex: 0xFF1C110C), text: Color(hex: 0xFFFBE9C8), muted: Color(hex: 0xFFC9A97F), accent: Color(hex: 0xFFE8B437), accent2: Color(hex: 0xFFB3271C), danger: Color(hex: 0xFFFF7A5A))
        default: // wood + the other plain "classic wooden" themes share the wood chrome palette
            return NUiPal(bg: Color(hex: 0xFF2A1A10), bg2: Color(hex: 0xFF3A2516), panel: Color(hex: 0xFF33200F), text: Color(hex: 0xFFFBEFD9), muted: Color(hex: 0xFFD8C2A0), accent: Color(hex: 0xFFE8A94B), accent2: Color(hex: 0xFFA9743B), danger: Color(hex: 0xFFD0644A))
        }
    }

    static func board(_ theme: String) -> NBoardPal {
        switch theme {
        case "oriental":
            return NBoardPal(frame: Color(hex: 0xFF4A2A17), frameIn: Color(hex: 0xFFC99A3C), felt: Color(hex: 0xFF0E5A5F), ptA: Color(hex: 0xFFC4572F), ptB: Color(hex: 0xFFF0DEB0), grain: 0.35, orn: Color(hex: 0xFFE0B04F), ornAlpha: 0.28,
                w1: Color(hex: 0xFFFFFAF0), w2: Color(hex: 0xFFEADCB8), w3: Color(hex: 0xFFB39B6A), b1: Color(hex: 0xFF3C5F99), b2: Color(hex: 0xFF1D3566), b3: Color(hex: 0xFF0B1630),
                hl: Color(hex: HL), sel: Color(hex: SEL), hinge: Color(hex: 0xFFE0B04F), ornStyle: "star")
        case "dark":
            return NBoardPal(frame: Color(hex: 0xFF07090D), frameIn: Color(hex: 0xFF2A3245), felt: Color(hex: 0xFF1B2130), ptA: Color(hex: 0xFF3B4A68), ptB: Color(hex: 0xFF8A6B3C), grain: 0, orn: Color(hex: 0xFF8FB4FF), ornAlpha: 0.12,
                w1: Color(hex: 0xFFFFFFFF), w2: Color(hex: 0xFFDFE5F0), w3: Color(hex: 0xFF8790A3), b1: Color(hex: 0xFF7A4A3A), b2: Color(hex: 0xFF4A241A), b3: Color(hex: 0xFF1A0B07),
                hl: Color(hex: HL), sel: Color(hex: SEL), hinge: Color(hex: 0xFF8FB4FF), ornStyle: "star")
        case "samarkand": // Majolica: cobalt, turquoise, white glaze, gold — girih star
            return NBoardPal(frame: Color(hex: 0xFF13306A), frameIn: Color(hex: 0xFFE3B04B), felt: Color(hex: 0xFF1F8A9E), ptA: Color(hex: 0xFF0E2F63), ptB: Color(hex: 0xFFF3ECD8), grain: 0, orn: Color(hex: 0xFFF3ECD8), ornAlpha: 0.30,
                w1: Color(hex: 0xFFFFFFFF), w2: Color(hex: 0xFFF1EBDC), w3: Color(hex: 0xFFB8AE92), b1: Color(hex: 0xFF4F7FD0), b2: Color(hex: 0xFF1A3F8A), b3: Color(hex: 0xFF0B1F4A),
                hl: Color(hex: HL), sel: Color(hex: SEL), hinge: Color(hex: 0xFFE3B04B), ornStyle: "star")
        case "suzani": // Uzbek embroidery: linen field, crimson rosettes, olive accents
            return NBoardPal(frame: Color(hex: 0xFF4A1A12), frameIn: Color(hex: 0xFFD9A441), felt: Color(hex: 0xFFF1E4C8), ptA: Color(hex: 0xFFA8202E), ptB: Color(hex: 0xFF5D7A35), grain: 0, orn: Color(hex: 0xFFB5222F), ornAlpha: 0.30,
                w1: Color(hex: 0xFFFFFBF2), w2: Color(hex: 0xFFF0E4CC), w3: Color(hex: 0xFFB8A27C), b1: Color(hex: 0xFFB0434A), b2: Color(hex: 0xFF6E1420), b3: Color(hex: 0xFF30060C),
                hl: Color(hex: 0xFF2E9E4F), sel: Color(hex: 0xFFE8A010), hinge: Color(hex: 0xFFD9A441), ornStyle: "suzani")
        case "iznik": // Turkish tiles: white tile, cobalt + turquoise points, red tulips
            return NBoardPal(frame: Color(hex: 0xFF123D73), frameIn: Color(hex: 0xFFD83C2B), felt: Color(hex: 0xFFFBF7EE), ptA: Color(hex: 0xFF1D4FA0), ptB: Color(hex: 0xFF2AA198), grain: 0, orn: Color(hex: 0xFFD83C2B), ornAlpha: 0.30,
                w1: Color(hex: 0xFFFFFFFF), w2: Color(hex: 0xFFF0EEEA), w3: Color(hex: 0xFFA9B3C0), b1: Color(hex: 0xFFE0614F), b2: Color(hex: 0xFFB8281A), b3: Color(hex: 0xFF5E0F08),
                hl: Color(hex: 0xFF2E9E4F), sel: Color(hex: 0xFFE8A010), hinge: Color(hex: 0xFFD83C2B), ornStyle: "tulip")
        case "aegean": // Greek sea blue field, white and navy, meander band
            return NBoardPal(frame: Color(hex: 0xFFE9E6DC), frameIn: Color(hex: 0xFF1D4F8A), felt: Color(hex: 0xFF2E6DB4), ptA: Color(hex: 0xFFF7F7F2), ptB: Color(hex: 0xFF123D6E), grain: 0, orn: Color(hex: 0xFFF7F7F2), ornAlpha: 0.40,
                w1: Color(hex: 0xFFFFFFFF), w2: Color(hex: 0xFFF2F2EC), w3: Color(hex: 0xFFA8B0BA), b1: Color(hex: 0xFF4A78B8), b2: Color(hex: 0xFF1B3F75), b3: Color(hex: 0xFF081A38),
                hl: Color(hex: HL), sel: Color(hex: SEL), hinge: Color(hex: 0xFF1D4F8A), ornStyle: "meander")
        case "carpet": // Caucasian carpet: madder red field, indigo and ivory, diamond medallion
            return NBoardPal(frame: Color(hex: 0xFF2B1A12), frameIn: Color(hex: 0xFFE0A63C), felt: Color(hex: 0xFF8E1F1F), ptA: Color(hex: 0xFF1D3557), ptB: Color(hex: 0xFFEFE2C4), grain: 0, orn: Color(hex: 0xFFEFE2C4), ornAlpha: 0.28,
                w1: Color(hex: 0xFFFFFAEE), w2: Color(hex: 0xFFEFE2C4), w3: Color(hex: 0xFFB5A27E), b1: Color(hex: 0xFF4A6FA5), b2: Color(hex: 0xFF1D3557), b3: Color(hex: 0xFF0A1628),
                hl: Color(hex: HL), sel: Color(hex: SEL), hinge: Color(hex: 0xFFE0A63C), ornStyle: "medallion")
        case "khokhloma": // black lacquer, cinnabar and gold, berries and curls
            return NBoardPal(frame: Color(hex: 0xFF0E0A08), frameIn: Color(hex: 0xFFE8B437), felt: Color(hex: 0xFF1A1210), ptA: Color(hex: 0xFFB3271C), ptB: Color(hex: 0xFFE8B437), grain: 0, orn: Color(hex: 0xFFE8B437), ornAlpha: 0.40,
                w1: Color(hex: 0xFFFFF2B0), w2: Color(hex: 0xFFE8B437), w3: Color(hex: 0xFF9A6E12), b1: Color(hex: 0xFFE0503C), b2: Color(hex: 0xFFB3271C), b3: Color(hex: 0xFF5A0C06),
                hl: Color(hex: HL), sel: Color(hex: 0xFFFFFFFF), hinge: Color(hex: 0xFFE8B437), ornStyle: "khokhloma")
        // ---- classic wooden boards ----
        case "beech":
            return NBoardPal(frame: Color(hex: 0xFF6B3F1D), felt: Color(hex: 0xFFE2B98A), ptA: Color(hex: 0xFF2B1A10), ptB: Color(hex: 0xFFF4E6C8), ornStyle: "none", trayA: 0.28)
        case "walnut":
            return NBoardPal(frame: Color(hex: 0xFF3A2414), felt: Color(hex: 0xFFB88452), ptA: Color(hex: 0xFF1C120C), ptB: Color(hex: 0xFFEFE0BF),
                orn: Color(hex: 0xFF5A3518), ornAlpha: 0.95, hinge: Color(hex: 0xFFD4A84A), ornStyle: "rosette", pointStyle: "inlay", trayA: 0.28)
        case "dragon":
            return NBoardPal(frame: Color(hex: 0xFF5A3418), felt: Color(hex: 0xFFD9A564), ptA: Color(hex: 0xFF1D120B), ptB: Color(hex: 0xFFF0DFC0), orn: Color(hex: 0xFF3E200C), ornStyle: "dragon", mirrorDecor: true, trayA: 0.28)
        case "pyro":
            return NBoardPal(frame: Color(hex: 0xFF7A4A22), felt: Color(hex: 0xFFE6C191), ptA: Color(hex: 0xFF3A1E0C), ptB: Color(hex: 0xFF3A1E0C), orn: Color(hex: 0xFF3A1E0C),
                hinge: Color(hex: 0xFFB8893A), ornStyle: "arabesque", pointStyle: "outlined", burn: Color(hex: 0xFF3A1E0C), trayA: 0.28)
        case "leather":
            return NBoardPal(frame: Color(hex: 0xFF4B2A1A), felt: Color(hex: 0xFFE9DCC0), ptA: Color(hex: 0xFF6B1F1F), ptB: Color(hex: 0xFF2E2A26), grain: 0.35,
                w1: Color(hex: 0xFFFFFBF0), w2: Color(hex: 0xFFEFE4CC), w3: Color(hex: 0xFFB8A27C), b1: Color(hex: 0xFFA8424A), b2: Color(hex: 0xFF6B1F1F), b3: Color(hex: 0xFF2A0808),
                hinge: Color(hex: 0xFFC0C0C0), ornStyle: "none", feltGrain: 0, stitch: Color(hex: 0xFFD9B47A), trayA: 0.28)
        case "knot":
            return NBoardPal(frame: Color(hex: 0xFF2E1D12), felt: Color(hex: 0xFFA8713F), ptA: Color(hex: 0xFF1A100A), ptB: Color(hex: 0xFFECD9B2),
                orn: Color(hex: 0xFF4A2810), hinge: Color(hex: 0xFFB08A3A), ornStyle: "knot", trayA: 0.28)
        case "mahogany":
            return NBoardPal(frame: Color(hex: 0xFF4A1A12), felt: Color(hex: 0xFF8E3B22), ptA: Color(hex: 0xFFF0DCB4), ptB: Color(hex: 0xFF1A0F0A),
                hinge: Color(hex: 0xFFD4A84A), ornStyle: "rhombus", pointStyle: "arrow", inlay: Color(hex: 0xFFEFDCB4), trayA: 0.28)
        case "ebony":
            return NBoardPal(frame: Color(hex: 0xFF0E0C0B), frameIn: Color(hex: 0xFF3A3020), felt: Color(hex: 0xFF1A1614), ptA: Color(hex: 0xFFEFE6D2), ptB: Color(hex: 0xFFC9A34A), grain: 0.15,
                orn: Color(hex: 0xFFC9A34A), ornAlpha: 0.95,
                w1: Color(hex: 0xFFFFFAF0), w2: Color(hex: 0xFFEFE6D2), w3: Color(hex: 0xFFB8AB8A), b1: Color(hex: 0xFF4A4440), b2: Color(hex: 0xFF1C1917), b3: Color(hex: 0xFF000000),
                hinge: Color(hex: 0xFFC9A34A), ornStyle: "rosette", feltGrain: 0.15,
                rim: Color(hex: 0xFFC9A34A), feltBorder: Color(hex: 0xFFC9A34A), ring: Color(hex: 0xFFC9A34A), trayA: 0.28)
        case "tournament":
            return NBoardPal(frame: Color(hex: 0xFF2A1A12), felt: Color(hex: 0xFF1F5A3A), ptA: Color(hex: 0xFFB3271C), ptB: Color(hex: 0xFFEFE6D2), grain: 0.3,
                hinge: Color(hex: 0xFFC0C0C0), ornStyle: "none", feltGrain: 0, stitch: Color(hex: 0xFF8A6A4A), trayA: 0.28)
        case "khatam":
            return NBoardPal(frame: Color(hex: 0xFF2A1A10), felt: Color(hex: 0xFFC9A36A), ptA: Color(hex: 0xFF2A1A12), ptB: Color(hex: 0xFFEFE0C0), grain: 0,
                hinge: Color(hex: 0xFFD4A84A), ornStyle: "starMed", pointStyle: "inlay", feltGrain: 0.55, khatam: true, trayA: 0.45)
        case "carve":
            return NBoardPal(frame: Color(hex: 0xFF5A3418), felt: Color(hex: 0xFFE8D6B0), ptA: Color(hex: 0xFF1F4F8A), ptB: Color(hex: 0xFFC99A3C), orn: Color(hex: 0xFF8A5A2A),
                w1: Color(hex: 0xFFFFFFFF), w2: Color(hex: 0xFFF1EBDC), w3: Color(hex: 0xFFB8AE92), b1: Color(hex: 0xFF4F7FD0), b2: Color(hex: 0xFF1A3F8A), b3: Color(hex: 0xFF0B1F4A),
                hinge: Color(hex: 0xFFC9A24A), ornStyle: "islimi", feltGrain: 0.3, trayA: 0.28)
        default: // "wood"
            return NBoardPal(frame: Color(hex: 0xFF5A3216), frameIn: Color(hex: 0xFF2B170A), felt: Color(hex: 0xFFD9A96A), ptA: Color(hex: 0xFF2C1A10), ptB: Color(hex: 0xFFF2E2C0), grain: 0.9, orn: Color(hex: 0xFF6B3D1A), ornAlpha: 0.22,
                w1: Color(hex: 0xFFFFFDF6), w2: Color(hex: 0xFFEFE3C8), w3: Color(hex: 0xFFBBA57A), b1: Color(hex: 0xFF6A5446), b2: Color(hex: 0xFF2C1F17), b3: Color(hex: 0xFF0B0705),
                hl: Color(hex: 0xFF3FBF5A), sel: Color(hex: 0xFFFFCF33), hinge: Color(hex: 0xFFC9A24A), ornStyle: "star")
        }
    }
}
