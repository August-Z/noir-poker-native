import SwiftUI
import PokerCore

private enum NoirPalette {
    static let ink = Color(red: 11/255, green: 16/255, blue: 23/255)
    static let panel = Color(red: 17/255, green: 25/255, blue: 35/255)
    static let mint = Color(red: 110/255, green: 231/255, blue: 197/255)
    static let text = Color(red: 237/255, green: 243/255, blue: 246/255)
    static let muted = Color(red: 136/255, green: 151/255, blue: 166/255)
    static let felt = Color(red: 20/255, green: 54/255, blue: 47/255)
}

struct ContentView: View {
    @State private var showRules = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Text("♠").font(.system(size: 34)).foregroundStyle(NoirPalette.mint)
                Text("NOIR").font(.system(size: 24, weight: .bold)).tracking(3)
                Text("POKER").font(.system(size: 15)).tracking(3).foregroundStyle(NoirPalette.muted)
            }
            Text("Offline Texas Hold’em practice").foregroundStyle(NoirPalette.muted)
            ZStack {
                RoundedRectangle(cornerRadius: 100).fill(NoirPalette.felt)
                RoundedRectangle(cornerRadius: 100).stroke(Color(red: 66/255, green: 88/255, blue: 96/255), lineWidth: 2)
                VStack(spacing: 20) {
                    Text("NOIR POKER").tracking(5).foregroundStyle(NoirPalette.mint.opacity(0.5))
                    HStack(spacing: 8) { PlayingCard(card: Card(rank: 14, suit: 0)); PlayingCard(card: Card(rank: 13, suit: 0)) }
                    Text("No account. Just practice.").font(.system(size: 13)).foregroundStyle(NoirPalette.muted)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Button("How to Play") { showRules = true }
                .buttonStyle(.bordered).tint(NoirPalette.mint).frame(maxWidth: .infinity)
            Text("Virtual chips only").font(.system(size: 12)).foregroundStyle(NoirPalette.muted).frame(maxWidth: .infinity)
        }
        .foregroundStyle(NoirPalette.text).padding(24)
        .background(NoirPalette.ink.ignoresSafeArea())
        .sheet(isPresented: $showRules) {
            NavigationStack {
                ScrollView {
                    Text("Each player receives two hole cards. Five community cards are dealt across the flop, turn, and river. Make the best five-card hand, or win when everyone else folds.\n\nCheck when no bet is owed. Otherwise, call, raise, or fold. This practice app uses virtual chips.")
                        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("How to Play")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got It") { showRules = false } } }
            }.tint(NoirPalette.mint).presentationDetents([.medium, .large])
        }
    }
}

private struct PlayingCard: View {
    let card: Card
    var body: some View {
        VStack(alignment: .leading) {
            Text(card.rankText).font(.system(size: 20, weight: .bold))
            Spacer()
            Text(card.symbol).font(.system(size: 28)).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(10).frame(width: 62, height: 88)
            .foregroundStyle(NoirPalette.ink).background(NoirPalette.text, in: RoundedRectangle(cornerRadius: 8))
    }
}
