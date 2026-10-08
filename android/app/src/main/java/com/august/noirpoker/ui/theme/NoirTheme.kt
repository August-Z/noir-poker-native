package com.august.noirpoker.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

/**
 * NOIR palette tokens (visual spec section 2). CSS `#rrggbbaa` values are written as
 * `Color(0xAARRGGBB)`: the alpha pair moves to the front.
 */
object Noir {
    // Root tokens.
    val Bg = Color(0xFF0B1017)
    val Panel = Color(0xFF111923)
    val Line = Color(0xFF25313D)
    val Muted = Color(0xFF8897A6)
    val Text = Color(0xFFEDF3F6)
    val Mint = Color(0xFF6EE7C5)
    val MintDark = Color(0xFF153D36)
    val Purple = Color(0xFFB4A2FF)
    val Red = Color(0xFFE56F80)
    val Felt = Color(0xFF14362F)

    // Neutrals and surfaces.
    val HeaderBorder = Color(0xFF202B35)
    val BrandLight = Color(0xFFA1B1BE)
    val HeaderCenter = Color(0xFFA7B6C3)
    val HeaderDivider = Color(0xFF35424E)
    val SurfaceBorder = Color(0xFF28353F)
    val SurfaceTop = Color(0xFF12242C)
    val SurfaceMid = Color(0xFF111C25)
    val SurfaceEdge = Color(0xFF101720)
    val CardBorder = Color(0xFF27333D)
    val CardTop = Color(0x8817202A)
    val CardBottom = Color(0x88111821)
    val CoachBorder = Color(0xFF33584F)
    val CoachTop = Color(0x66142E29)
    val CoachBottom = Color(0x66142128)
    val DialogBg = Color(0xFF14202A)
    val DialogBorder = Color(0xFF3B504F)
    val SelectBg = Color(0xFF1B2632)
    val SelectText = Color(0xFFD2DBE3)
    val SelectBorder = Color(0xFF34404A)
    val StripDivider = Color(0xFF253039)
    val StatsDivider = Color(0xFF2A3540)

    // Text greys.
    val TextSurfaceTop = Color(0xFF9CB0BF)
    val TextStrip = Color(0xFFA7B8C4)
    val TextSliderLabel = Color(0xFF8093A3)
    val TextFooter = Color(0xFF8193A1) // `#697d8c` nudged lighter for contrast.
    val TextSubtle = Color(0xFF7C909F)
    val TextDialogBody = Color(0xFFA8BDC7)
    val TextEyebrow = Color(0xFF7F9B9C)
    val TextFootnote = Color(0xFF75899A) // `#5d7180` nudged lighter for contrast.

    // Felt and table.
    val RailA = Color(0xFF31434C)
    val RailB = Color(0xFF16232D)
    val RailC = Color(0xFF31464B)
    val RailBorder = Color(0xFF425860)
    val FeltLight = Color(0xFF16433E)
    val FeltDark = Color(0xFF102E2B)
    val FeltBorder = Color(0x55438B79)
    val FeltOutline = Color(0x226EE7C5)
    val FeltDot = Color(0x08B3FFDC)
    val Watermark = Color(0x2276B8A5)
    val SlotBorder = Color(0x3073A998)
    val SlotBg = Color(0x200E2624)
    val SlotGlyph = Color(0x2081B9A4)

    // Seats.
    val PlateBg = Color(0xFF131E29)
    val PlateBorder = Color(0xFF3B4B5A)
    val PlateFoldedBg = Color(0xFF101923)
    val PlateFoldedBorder = Color(0xFF394449)
    val AvatarFills = listOf(
        Color(0xFF394D69) to Color(0xFFC9E1FF),
        Color(0xFF755845) to Color(0xFFFFDDBE),
        Color(0xFF3E625E) to Color(0xFFB8EFE2),
        Color(0xFF685261) to Color(0xFFF1D0E3),
    )
    val AvatarDefault = Color(0xFF564968) to Color(0xFFE0D0F8)
    val StyleBorder = Color(0xFF62988B)
    val StyleBg = Color(0xFF1B3D35)
    val StyleText = Color(0xFFCFF0E4)
    val MoodHot = Color(0xFFD89568)
    val MoodCautious = Color(0xFFA2B4D9)
    val MoodConfident = Color(0xFFE1C173)
    val SeatStack = Color(0xFF89A4B0)
    val SeatActionLabel = Color(0xFF91ABAE)
    val SeatActionAmount = Color(0xFFC8DDD3)
    val PeekBorder = Color(0xFF527266)
    val PeekPressedBg = Color(0xFF24483E)
    val PeekPressedBorder = Color(0xFF70B49B)

    // Position badges.
    val BadgeBg = Color(0xFF273642)
    val BadgeText = Color(0xFFB3C5CF)
    val BtnBg = Color(0xFFE3E9DF)
    val BtnText = Color(0xFF26322E)
    val SbBg = Color(0xFF265149)
    val SbText = Color(0xFF9EE3CA)
    val BbBg = Color(0xFF354A63)
    val BbText = Color(0xFFC5DDF5)

    // Turn and winner accents.
    val TurnGlow = Color(0x236EE7C5)
    val Gold = Color(0xFFD2B36B)
    val GoldSettled = Color(0xFFE3BF72)
    val GoldText = Color(0xFFE6D3A2)
    val GoldBright = Color(0xFFF4D99E)
    val GoldPale = Color(0xFFEBD097)
    val GoldBadgeBg = Color(0xFF483E26)
    val GoldBadgeText = Color(0xFFFFE0A0)
    val GoldMuted = Color(0xFF8B794A)
    val GoldEyebrow = Color(0xFFB7A57D)
    val GoldNote = Color(0xFFE3C588)
    val ReplayBorder = Color(0xFF82724D)
    val ReplayText = Color(0xFFE5CE98)
    val ReplayBg = Color(0x66332D1F)

    // Rank badge.
    val RankBg = Color(0xFF23483F)
    val RankText = Color(0xFFC6F1DF)
    val RankBorder = Color(0x5C5CBFA3)

    // Review purples.
    val ReviewBorder = Color(0xFF736088)
    val ReviewBg = Color(0x66493658)
    val ReviewText = Color(0xFFDDCAFA)
    val ReviewEyebrow = Color(0xFFB3A0CA)

    // Negative.
    val Negative = Color(0xFFDD8993)

    // Activity log.
    val LogHero = Color(0xFF8DDBBE)
    val LogResult = Color(0xFFE2CD8E)
    val LogStreet = Color(0xFFCFDEE2)
    val LogDefault = Color(0xFF8EA3B2)

    // Buttons.
    val OnMint = Color(0xFF0C3026)
    val RaiseText = Color(0xFF092A22)
    val CallBg = Color(0xFF24383E)
    val CallText = Color(0xFFC6E3DC)
    val CallBorder = Color(0xFF48635F)
    val FoldBg = Color(0xFF222B36)
    val FoldText = Color(0xFFB1BDC9)
    val FoldBorder = Color(0xFF38414D)
    val FinishBg = Color(0xFF183F36)
    val FinishBorder = Color(0xFF648C7F)
    val FinishText = Color(0xFFBCF2DD)
    val PresetBg = Color(0xFF18222D)
    val PresetBorder = Color(0xFF2B3945)
    val SliderTrack = Color(0xFF2B3945)

    // Cards.
    val CardFaceA = Color(0xFFFFFDF8)
    val CardFaceB = Color(0xFFF3F5F0)
    val CardFaceC = Color(0xFFE5EEEC)
    val CardEdge = Color(0xFFEDF6F3)
    val CardInk = Color(0xFF223447)
    val CardRed = Color(0xFFC74760)
    val CardRule = Color(0x1A344D60)
    val BackBase = Color(0xFF1B3947)
    val BackLineA = Color(0x40568C95)
    val BackLineB = Color(0x50609398)
    val BackBorder = Color(0xFF7DA8AD)

    // Showdown stage.
    val ShowdownBorder = Color(0xFF445344)
    val ShowdownBg = Color(0xFF101B22)
    val ScenePanel = Color(0xFF12232A)
    val ScenePanelBorder = Color(0xFF2C4342)
    val SceneName = Color(0xFFE0EAE7)
    val SceneLoser = Color(0xFF8FA9A6)
    val SceneHand = Color(0xFFC4DBD1)
    val SceneMatch = Color(0xFFDFC285)
    val SceneLoserOutline = Color(0xFF77B6A6)

    // Flying chips.
    val ChipFill = Color(0xFF276452)
    val ChipEdge = Color(0xFFAEF5D3)

    /** Avatar background and text for an opponent seat id (1-based). */
    fun avatar(seat: Int): Pair<Color, Color> = AvatarFills.getOrNull(seat - 1) ?: AvatarDefault
}

/**
 * Type scale (visual spec section 3.1). Sizes are in `sp`, so they follow the
 * system font scale. The app installs the bundled Manrope family (SIL OFL) at
 * startup; the platform sans serif stands in until then (and in previews).
 */
@Suppress("ConstPropertyName")
object NoirType {
    var family: FontFamily = FontFamily.SansSerif
        private set

    /** Installs the brand family; call once before the first composition. */
    fun install(family: FontFamily) {
        this.family = family
    }

    fun style(size: TextUnit, weight: FontWeight = FontWeight.Normal, color: Color = Noir.Text, tracking: TextUnit = 0.sp) =
        TextStyle(fontFamily = family, fontSize = size, fontWeight = weight, color = color, letterSpacing = tracking)

    /** Tabular figures for chip amounts and numbered lists. */
    fun tabular(style: TextStyle): TextStyle = style.copy(fontFeatureSettings = "tnum")
}

/** Layout density of the table, chosen from the window width and font scale. */
data class NoirMetrics(
    /** ≤600 dp wide (phone portrait). */
    val compact: Boolean,
    /** Two panes: the table and a 284 dp sidebar. */
    val twoPane: Boolean,
    /** Large accessibility text (font scale ≥ 1.3): denser seats, no avatars. */
    val largeText: Boolean,
    /** ≤360 dp wide: the tightest phone rules. */
    val tiny: Boolean,
)

val LocalNoirMetrics = staticCompositionLocalOf { NoirMetrics(compact = true, twoPane = false, largeText = false, tiny = false) }

/** Reduced motion: skip deal, flip, glow and chip animations. */
val LocalReducedMotion = staticCompositionLocalOf { false }

@Composable
fun NoirTheme(reducedMotion: Boolean = false, content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Noir.Mint,
            onPrimary = Noir.OnMint,
            background = Noir.Bg,
            onBackground = Noir.Text,
            surface = Noir.DialogBg,
            onSurface = Noir.Text,
            surfaceContainerLow = Noir.DialogBg,
            surfaceContainer = Noir.DialogBg,
            surfaceContainerHigh = Noir.DialogBg,
            outline = Noir.Line,
            secondary = Noir.Mint,
        ),
    ) {
        CompositionLocalProvider(LocalReducedMotion provides reducedMotion, content = content)
    }
}
