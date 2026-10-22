import SwiftUI

/// Companion app: setup guide + a box to try the keyboard. The keyboard itself lives in the
/// KeshuKeyboard extension; iOS gives apps no reliable way to check whether it's enabled.
struct ContentView: View {
    @State private var practiceText = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Write with your finger and it gets typed in Hindi.")
                        .font(.title3)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Step(number: 1, text: "Open Settings → General → Keyboard → Keyboards.")
                            Step(number: 2, text: "Tap “Add New Keyboard…” and choose “Keshu Keyboard”.")
                            Step(number: 3, text: "Tap “Keshu Keyboard” and turn on “Allow Full Access”. It's needed once, to download Hindi recognition (about 20 MB).")
                            Step(number: 4, text: "In any app, tap 🌐 on the keyboard to switch to Keshu Keyboard.")
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            } label: {
                                Text("Open Settings")
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } label: {
                        Text("Turn on the keyboard").font(.title2.bold())
                    }

                    GroupBox {
                        TextField("Tap here, switch to Keshu Keyboard and write", text: $practiceText, axis: .vertical)
                            .font(.title2)
                            .lineLimit(3...8)
                            .padding(.vertical, 8)
                    } label: {
                        Text("Try writing").font(.title2.bold())
                    }
                }
                .padding()
            }
            .navigationTitle("Keshu Keyboard")
        }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).").font(.title3.bold())
            Text(text).font(.title3)
        }
    }
}
