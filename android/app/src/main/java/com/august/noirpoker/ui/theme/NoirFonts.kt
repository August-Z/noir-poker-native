package com.august.noirpoker.ui.theme

// android-only: font resources from res/font (Manrope, SIL Open Font License 1.1;
// the license text ships in assets/licenses/manrope-OFL.txt).

import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.august.noirpoker.R

/** Manrope 400–800, the reference's UI and card-rank face. */
val ManropeFamily: FontFamily = FontFamily(
    Font(R.font.manrope_regular, FontWeight.Normal),
    Font(R.font.manrope_medium, FontWeight.Medium),
    Font(R.font.manrope_semibold, FontWeight.SemiBold),
    Font(R.font.manrope_bold, FontWeight.Bold),
    Font(R.font.manrope_extrabold, FontWeight.ExtraBold),
)
