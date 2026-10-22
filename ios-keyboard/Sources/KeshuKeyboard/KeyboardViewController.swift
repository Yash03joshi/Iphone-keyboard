import UIKit

/// The Hindi handwriting keyboard. Write a word, pause, and the best guess is typed with a
/// trailing space; the suggestion strip replaces that word with another guess.
/// Port of the Android `HindiInputMethodService`, styled after Gboard.
@objc(KeyboardViewController)
final class KeyboardViewController: UIInputViewController {
    private enum Page { case write, symbols, moreSymbols }

    private static let hint = "Write here"
    private static let recognizeDelay: TimeInterval = 0.9
    private static let preContextLength = 20
    private static let suggestionSlots = 3
    private static let keyHeight: CGFloat = 46
    private static let keyGap: CGFloat = 6
    private static let rowGap: CGFloat = 10
    private static let stripHeight: CGFloat = 44
    private static let canvasHeight: CGFloat = 220
    private static let bottomInset: CGFloat = 6

    // Gboard-style symbol pages; each has 3 rows above the shared bottom row.
    private static let symbols = ["1234567890", "@#₹_&-+()/", "*\"':;!?"]
    private static let moreSymbols = ["~`|•√π÷×।∆", "£¢€¥^°={}\\", "%©®™✓[]"]

    // Marks that attach to the previous word: an auto-inserted space before them is removed.
    private static let closingMarks = Set(".,?!:;)]}%।")

    private let rootStack = UIStackView()
    private let suggestionStrip = UIStackView()
    private let writingBox = UIView()
    private let canvas = HandwritingView()
    private let hintLabel = UILabel()
    private let modelBox = UIView()
    private let modelMessage = UILabel()
    private let modelButton = KeyButton(title: "Download", style: .accent, fontSize: 18, weight: .semibold)
    private var symbolPages: [UIView] = []
    private var writeRow = UIView()
    private var symbolRow = UIView()
    private var globeKey: KeyButton?
    private var heightConstraint: NSLayoutConstraint?
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    private var page = Page.write
    private var modelReady = true

    // The text typed by the last recognition (incl. any leading/trailing space), so a
    // suggestion tap can replace it. Cleared by any other edit.
    private var lastCommit: String?
    private var lastPrefix = ""
    private var lastCandidates: [String] = []

    private var recognizing = false
    private var pausedWhileRecognizing = false
    private var deleteTimer: Timer?

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        show(.write)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        canvas.clear()
        clearSuggestions()
        show(.write)
        refreshModelState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        stopDeleteRepeat()
        canvas.clear()
        clearSuggestions()
        // Keyboard extensions have a tight memory limit; reload the model on next use.
        InkRecognizer.shared.releaseRecognizer()
        super.viewWillDisappear(animated)
    }

    override func viewWillLayoutSubviews() {
        // iPhones with a home indicator show their own globe key below the keyboard.
        globeKey?.isHidden = !needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    // MARK: Recognition

    private func writingPaused() {
        if recognizing {
            pausedWhileRecognizing = true
            return
        }
        guard canvas.strokeCount > 0, !canvas.isWriting else { return }

        let strokeCount = canvas.strokeCount
        let preContext = String((textDocumentProxy.documentContextBeforeInput ?? "").suffix(Self.preContextLength))
        recognizing = true
        InkRecognizer.shared.recognize(canvas.buildInk(), preContext: preContext, writingArea: canvas.bounds.size) { [weak self] result in
            guard let self else { return }
            recognizing = false
            switch result {
            case .success(let candidates):
                var seen = Set<String>()
                let words = candidates
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && seen.insert($0).inserted }
                if !words.isEmpty { commitRecognized(words) }
                canvas.removeFirstStrokes(strokeCount)
            case .failure:
                setHint("Couldn't read that, please write again", Palette.danger)
                canvas.clear()
                refreshModelState()
            }
            if pausedWhileRecognizing {
                pausedWhileRecognizing = false
                writingPaused()
            }
        }
    }

    // MARK: Text editing

    private var proxy: UITextDocumentProxy { textDocumentProxy }

    private func commitRecognized(_ words: [String]) {
        let before = proxy.documentContextBeforeInput ?? ""
        // Separate from a word the user typed without a trailing space.
        lastPrefix = before.last.map { $0.isWhitespace } == false ? " " : ""
        let text = lastPrefix + words[0] + " "
        proxy.insertText(text)
        lastCommit = text
        lastCandidates = Array(words.prefix(Self.suggestionSlots))
        showSuggestions(chosen: 0)
    }

    private func chooseSuggestion(_ index: Int) {
        guard let previous = lastCommit, lastCandidates.indices.contains(index) else { return }
        guard (proxy.documentContextBeforeInput ?? "").hasSuffix(previous) else {
            // The text changed since we typed it (cursor moved, user edited); don't clobber it.
            clearSuggestions()
            return
        }
        deleteBackward(scalarCount: previous.unicodeScalars.count)
        let text = lastPrefix + lastCandidates[index] + " "
        proxy.insertText(text)
        lastCommit = text
        showSuggestions(chosen: index)
    }

    /// Deletes exactly `scalarCount` Unicode scalars. A single deleteBackward may remove one
    /// scalar (a Devanagari matra) or a whole cluster depending on the host, so re-measure.
    private func deleteBackward(scalarCount: Int) {
        var remaining = scalarCount
        while remaining > 0 {
            let before = proxy.documentContextBeforeInput?.unicodeScalars.count ?? 0
            proxy.deleteBackward()
            let after = proxy.documentContextBeforeInput?.unicodeScalars.count ?? 0
            remaining -= max(before - after, 1)
        }
    }

    /// Removes the last stroke if there is unrecognized ink, otherwise deletes text.
    private func backspace() {
        if canvas.strokeCount > 0 {
            canvas.undoStroke()
            return
        }
        clearSuggestions()
        proxy.deleteBackward()
    }

    private func typeSymbol(_ symbol: String) {
        // Right after a recognized word: "नमस्ते ," → "नमस्ते, " (keep the space after the mark).
        let attach = lastCommit != nil
            && symbol.count == 1 && Self.closingMarks.contains(symbol.first!)
            && proxy.documentContextBeforeInput?.hasSuffix(" ") == true
        clearSuggestions()
        if attach {
            proxy.deleteBackward()
            proxy.insertText(symbol + " ")
        } else {
            proxy.insertText(symbol)
        }
    }

    private func typeSpace() {
        clearSuggestions()
        proxy.insertText(" ")
    }

    private func enter() {
        clearSuggestions()
        // Hosts treat a newline as their return-key action (send, search, go…).
        proxy.insertText("\n")
    }

    @objc private func deleteDown() {
        feedback()
        backspace()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] timer in
                // Only repeat-delete typed text; never wipe the user's ink in one long press.
                guard let self, canvas.strokeCount == 0 else {
                    timer.invalidate()
                    return
                }
                backspace()
            }
        }
    }

    @objc private func stopDeleteRepeat() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    private func feedback() {
        // Haptics only work in keyboards with Full Access.
        if hasFullAccess { haptics.impactOccurred() }
    }

    // MARK: Model state

    private func refreshModelState() {
        modelReady = InkRecognizer.shared.isModelDownloaded
        if modelReady {
            setHint(Self.hint, Palette.muted)
        } else if hasFullAccess {
            modelMessage.text = "Hindi recognition needs a one-time download (about 20 MB)."
            modelButton.isHidden = false
        } else {
            modelMessage.text = "To download Hindi recognition once, turn on Allow Full Access:\n"
                + "Settings → General → Keyboard → Keyboards → Keshu Keyboard"
            modelButton.isHidden = true
        }
        applyPage()
    }

    private func downloadModel() {
        modelMessage.text = "Downloading… please wait."
        modelButton.isEnabled = false
        InkRecognizer.shared.downloadModel { [weak self] error in
            guard let self else { return }
            modelButton.isEnabled = true
            if error == nil {
                refreshModelState()
            } else {
                modelMessage.text = "Download failed. Turn on the internet and try again."
            }
        }
    }

    // MARK: Pages

    private func show(_ newPage: Page) {
        if newPage != .write, page == .write { canvas.clear() }
        page = newPage
        applyPage()
    }

    private func applyPage() {
        writingBox.isHidden = page != .write || !modelReady
        modelBox.isHidden = page != .write || modelReady
        symbolPages[0].isHidden = page != .symbols
        symbolPages[1].isHidden = page != .moreSymbols
        writeRow.isHidden = page != .write
        symbolRow.isHidden = page == .write

        // Symbol pages size to their keys (like Gboard), not to the taller writing area.
        let body = page == .write
            ? Self.canvasHeight
            : 3 * Self.keyHeight + 2 * Self.rowGap
        heightConstraint?.constant = Self.stripHeight + body + Self.rowGap + Self.keyHeight + Self.bottomInset
    }

    // MARK: Layout

    private func buildLayout() {
        view.backgroundColor = Palette.background

        rootStack.axis = .vertical
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)

        let height = view.heightAnchor.constraint(equalToConstant: 300)
        height.priority = UILayoutPriority(999)
        heightConstraint = height

        NSLayoutConstraint.activate([
            height,
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -Self.bottomInset),
        ])

        suggestionStrip.axis = .horizontal
        suggestionStrip.alignment = .center
        suggestionStrip.spacing = 4
        suggestionStrip.heightAnchor.constraint(equalToConstant: Self.stripHeight).isActive = true
        rootStack.addArrangedSubview(suggestionStrip)

        buildWritingBox()
        rootStack.addArrangedSubview(writingBox)
        rootStack.setCustomSpacing(Self.rowGap, after: writingBox)

        buildModelBox()
        rootStack.addArrangedSubview(modelBox)
        rootStack.setCustomSpacing(Self.rowGap, after: modelBox)

        symbolPages = [
            symbolPage(Self.symbols, switchTitle: "=\\<", switchTo: .moreSymbols),
            symbolPage(Self.moreSymbols, switchTitle: "?123", switchTo: .symbols),
        ]
        for symbolPage in symbolPages {
            rootStack.addArrangedSubview(symbolPage)
            rootStack.setCustomSpacing(Self.rowGap, after: symbolPage)
        }

        writeRow = buildWriteRow()
        symbolRow = buildSymbolRow()
        rootStack.addArrangedSubview(writeRow)
        rootStack.addArrangedSubview(symbolRow)
    }

    private func buildWritingBox() {
        writingBox.backgroundColor = Palette.canvas
        writingBox.layer.cornerRadius = 12
        writingBox.clipsToBounds = true
        writingBox.heightAnchor.constraint(equalToConstant: Self.canvasHeight).isActive = true

        canvas.pauseDelay = Self.recognizeDelay
        canvas.inkColor = Palette.ink
        canvas.onStrokesChanged = { [weak self] count in
            self?.hintLabel.isHidden = count > 0
        }
        canvas.onWritingPaused = { [weak self] in
            self?.writingPaused()
        }

        hintLabel.font = .systemFont(ofSize: 22)
        hintLabel.textAlignment = .center
        hintLabel.isUserInteractionEnabled = false
        setHint(Self.hint, Palette.muted)

        for subview in [canvas, hintLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            writingBox.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: writingBox.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: writingBox.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: writingBox.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: writingBox.trailingAnchor),
            hintLabel.centerXAnchor.constraint(equalTo: writingBox.centerXAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: writingBox.centerYAnchor),
        ])
    }

    private func buildModelBox() {
        modelBox.backgroundColor = Palette.canvas
        modelBox.layer.cornerRadius = 12
        modelBox.heightAnchor.constraint(equalToConstant: Self.canvasHeight).isActive = true

        modelMessage.font = .systemFont(ofSize: 17)
        modelMessage.textColor = Palette.text
        modelMessage.textAlignment = .center
        modelMessage.numberOfLines = 0

        modelButton.onTap = { [weak self] in self?.downloadModel() }
        modelButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        modelButton.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let content = UIStackView(arrangedSubviews: [modelMessage, modelButton])
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        modelBox.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerYAnchor.constraint(equalTo: modelBox.centerYAnchor),
            content.leadingAnchor.constraint(equalTo: modelBox.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: modelBox.trailingAnchor, constant: -16),
        ])
    }

    private func buildWriteRow() -> UIView {
        let globe = KeyButton(systemImage: "globe", style: .function)
        globe.accessibilityLabel = "Switch keyboard"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globeKey = globe

        return keyRow([
            (key("?123", style: .function, fontSize: 16, weight: .semibold) { [weak self] in self?.show(.symbols) }, 1.4),
            (globe, 1.2),
            (key(",", style: .function) { [weak self] in self?.typeSymbol(",") }, 1),
            (spaceKey(), 4),
            (deleteKey(), 1.5),
            (enterKey(), 1.5),
        ])
    }

    private func buildSymbolRow() -> UIView {
        let write = key("अ", style: .function, fontSize: 20, weight: .semibold) { [weak self] in self?.show(.write) }
        write.accessibilityLabel = "Handwriting"
        return keyRow([
            (write, 1.4),
            (key(",", style: .function) { [weak self] in self?.typeSymbol(",") }, 1),
            (spaceKey(), 4.2),
            (key(".", style: .function) { [weak self] in self?.typeSymbol(".") }, 1),
            (enterKey(), 1.5),
        ])
    }

    /// Three rows of symbol keys; the last row starts with a page switch and ends with delete.
    private func symbolPage(_ rows: [String], switchTitle: String, switchTo: Page) -> UIView {
        func symbolKeys(_ chars: String) -> [(UIView, CGFloat)] {
            chars.map { char in
                let symbol = String(char)
                return (key(symbol, style: .character) { [weak self] in self?.typeSymbol(symbol) }, 1)
            }
        }
        let switchKey = key(switchTitle, style: .function, fontSize: 16, weight: .semibold) { [weak self] in
            self?.show(switchTo)
        }
        let page = UIStackView(arrangedSubviews: [
            keyRow(symbolKeys(rows[0])),
            keyRow(symbolKeys(rows[1])),
            keyRow([(switchKey, 1.5)] + symbolKeys(rows[2]) + [(deleteKey(), 1.5)]),
        ])
        page.axis = .vertical
        page.spacing = Self.rowGap
        return page
    }

    /// A row of keys whose widths keep the given proportions.
    private func keyRow(_ keys: [(UIView, CGFloat)]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: keys.map { $0.0 })
        row.axis = .horizontal
        row.spacing = Self.keyGap
        row.heightAnchor.constraint(equalToConstant: Self.keyHeight).isActive = true
        guard let firstKey = keys.first else { return row }
        let (first, firstWeight) = firstKey
        for (view, weight) in keys.dropFirst() {
            // Below required so a hidden key (the globe) can collapse to zero width.
            let width = view.widthAnchor.constraint(equalTo: first.widthAnchor, multiplier: weight / firstWeight)
            width.priority = UILayoutPriority(999)
            width.isActive = true
        }
        return row
    }

    private func key(
        _ title: String,
        style: KeyButton.Style,
        fontSize: CGFloat = 22,
        weight: UIFont.Weight = .regular,
        action: @escaping () -> Void
    ) -> KeyButton {
        let button = KeyButton(title: title, style: style, fontSize: fontSize, weight: weight)
        button.onTap = { [weak self] in
            self?.feedback()
            action()
        }
        return button
    }

    private func spaceKey() -> KeyButton {
        let space = KeyButton(title: "Space", style: .character, fontSize: 16, textColor: Palette.muted)
        space.onTap = { [weak self] in
            self?.feedback()
            self?.typeSpace()
        }
        return space
    }

    private func enterKey() -> KeyButton {
        let enter = KeyButton(systemImage: "return", style: .accent)
        enter.accessibilityLabel = "Enter"
        enter.onTap = { [weak self] in
            self?.feedback()
            self?.enter()
        }
        return enter
    }

    /// Delete key that repeats while held.
    private func deleteKey() -> KeyButton {
        let delete = KeyButton(systemImage: "delete.left", style: .function)
        delete.accessibilityLabel = "Delete"
        delete.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        delete.addTarget(self, action: #selector(stopDeleteRepeat), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return delete
    }

    // MARK: Suggestions

    /// Gboard-style strip: equal slots split by thin dividers, the word in the text highlighted.
    private func showSuggestions(chosen: Int) {
        clearSuggestionViews()
        var firstSlot: UIView?
        for (index, word) in lastCandidates.enumerated() {
            if index > 0 {
                let divider = UIView()
                divider.backgroundColor = Palette.divider
                divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
                divider.heightAnchor.constraint(equalToConstant: 24).isActive = true
                suggestionStrip.addArrangedSubview(divider)
            }
            let isChosen = index == chosen
            var config = UIButton.Configuration.plain()
            config.title = word
            config.baseForegroundColor = Palette.text
            config.background.backgroundColor = isChosen ? Palette.chosen : .clear
            config.background.cornerRadius = 20
            config.titleLineBreakMode = .byTruncatingTail
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: 22, weight: isChosen ? .semibold : .regular)
                return attributes
            }
            let slot = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
                self?.feedback()
                self?.chooseSuggestion(index)
            })
            slot.heightAnchor.constraint(equalToConstant: 38).isActive = true
            suggestionStrip.addArrangedSubview(slot)
            if let firstSlot {
                slot.widthAnchor.constraint(equalTo: firstSlot.widthAnchor).isActive = true
            } else {
                firstSlot = slot
            }
        }
    }

    private func clearSuggestions() {
        lastCommit = nil
        lastCandidates = []
        clearSuggestionViews()
    }

    private func clearSuggestionViews() {
        for view in suggestionStrip.arrangedSubviews {
            view.removeFromSuperview()
        }
    }

    private func setHint(_ text: String, _ color: UIColor) {
        hintLabel.text = text
        hintLabel.textColor = color
    }
}
