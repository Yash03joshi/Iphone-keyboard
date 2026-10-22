import UIKit

/// A Gboard-style key: rounded, 1pt bottom shadow, darker while pressed.
final class KeyButton: UIControl {
    enum Style {
        case character, function, accent

        var fill: UIColor {
            switch self {
            case .character: Palette.key
            case .function: Palette.functionKey
            case .accent: Palette.accent
            }
        }

        var foreground: UIColor {
            self == .accent ? Palette.onAccent : Palette.text
        }
    }

    /// Called on touch-up-inside.
    var onTap: (() -> Void)?

    private let style: Style
    private let label = UILabel()
    private let icon = UIImageView()

    init(
        title: String? = nil,
        systemImage: String? = nil,
        style: Style,
        fontSize: CGFloat = 22,
        weight: UIFont.Weight = .regular,
        textColor: UIColor? = nil
    ) {
        self.style = style
        super.init(frame: .zero)

        layer.cornerRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 1

        let content: UIView
        if let systemImage {
            icon.image = UIImage(
                systemName: systemImage,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            )
            icon.tintColor = style.foreground
            icon.contentMode = .center
            content = icon
        } else {
            label.text = title
            label.font = .systemFont(ofSize: fontSize, weight: weight)
            label.textColor = textColor ?? style.foreground
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            content = label
        }
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        accessibilityLabel = title

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (key: KeyButton, _) in
            key.updateColors()
        }
        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isHighlighted: Bool {
        didSet { updateColors() }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }
    }

    func setTitle(_ title: String) {
        label.text = title
        accessibilityLabel = title
    }

    private func updateColors() {
        let fill = style.fill.resolvedColor(with: traitCollection)
        backgroundColor = isHighlighted ? fill.withAlphaComponent(0.6) : fill
        layer.shadowColor = Palette.keyShadow.resolvedColor(with: traitCollection).cgColor
    }

    @objc private func tapped() {
        onTap?()
    }
}
