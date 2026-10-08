package com.august.noirpoker

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val Ink = Color(0xFF0B1017)
private val Panel = Color(0xFF111923)
private val Mint = Color(0xFF6EE7C5)
private val Text = Color(0xFFEDF3F6)
private val Muted = Color(0xFF8897A6)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { NoirApp() }
    }
}

@Composable
fun NoirApp() {
    var showRules by remember { mutableStateOf(false) }
    MaterialTheme(colorScheme = darkColorScheme(primary = Mint, background = Ink, surface = Panel, onBackground = Text, onSurface = Text)) {
        Column(Modifier.fillMaxSize().background(Ink).safeDrawingPadding().padding(24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("♠", color = Mint, fontSize = 34.sp)
                Spacer(Modifier.width(12.dp))
                Text("NOIR", fontWeight = FontWeight.Bold, fontSize = 24.sp, letterSpacing = 3.sp)
                Spacer(Modifier.width(8.dp))
                Text("POKER", color = Muted, fontSize = 15.sp, letterSpacing = 3.sp)
            }
            Text("Offline Texas Hold’em practice", color = Muted)
            Box(Modifier.fillMaxWidth().weight(1f).background(Color(0xFF14362F), RoundedCornerShape(100.dp)).border(2.dp, Color(0xFF425860), RoundedCornerShape(100.dp)), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    Text("NOIR POKER", color = Mint.copy(alpha = 0.5f), letterSpacing = 5.sp)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { PlayingCard("A", "♠"); PlayingCard("K", "♠") }
                    Text("No account. Just practice.", color = Muted, fontSize = 13.sp)
                }
            }
            OutlinedButton(onClick = { showRules = true }, modifier = Modifier.fillMaxWidth()) { Text("How to Play") }
            Text("Virtual chips only", color = Muted, fontSize = 12.sp, modifier = Modifier.align(Alignment.CenterHorizontally))
            if (showRules) AlertDialog(onDismissRequest = { showRules = false }, title = { Text("How to Play") }, text = { Text("Each player receives two hole cards. Five community cards are dealt across the flop, turn, and river. Make the best five-card hand, or win when everyone else folds.\n\nCheck when no bet is owed. Otherwise, call, raise, or fold. This practice app uses virtual chips.") }, confirmButton = { TextButton(onClick = { showRules = false }) { Text("Got It") } })
        }
    }
}

@Composable
private fun PlayingCard(rank: String, suit: String) {
    Column(Modifier.size(62.dp, 88.dp).background(Color(0xFFEDF3F6), RoundedCornerShape(8.dp)).padding(10.dp), verticalArrangement = Arrangement.SpaceBetween) {
        Text(rank, color = Ink, fontWeight = FontWeight.Bold, fontSize = 20.sp)
        Text(suit, color = Ink, fontSize = 28.sp, modifier = Modifier.align(Alignment.End))
    }
}

