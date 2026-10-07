import GoogleMobileAds
import SwiftUI

/// A native ad drawn in the Metro style. Google needs the ad in its own `NativeAdView` with each asset registered,
/// so it's built in UIKit.
struct NativeAdCard: UIViewRepresentable {
    let ad: NativeAd
    let palette: MetroPalette

    func makeUIView(context: Context) -> MetroNativeAdView {
        MetroNativeAdView()
    }

    func updateUIView(_ view: MetroNativeAdView, context: Context) {
        view.show(ad, palette: palette)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MetroNativeAdView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: uiView.fittingHeight(for: width))
    }
}

final class MetroNativeAdView: NativeAdView {
    private let badge = UILabel()
    private let media = MediaView()
    private let headline = UILabel()
    private let bodyText = UILabel()
    private let icon = UIImageView()
    private let advertiser = UILabel()
    private let action = InsetLabel()
    private let stack = UIStackView()
    private let footer = UIStackView()
    private var mediaRatio: NSLayoutConstraint?
    private var shownAd: NativeAd?
    private var shownPalette: MetroPalette?
    /// Registered once the view has its size; Google checks that every asset sits inside the ad view.
    private var pendingAd: NativeAd?

    override init(frame: CGRect) {
        super.init(frame: frame)

        badge.text = "SPONSORED"
        badge.font = Self.font(.semibold, 12, .caption2)
        badge.adjustsFontForContentSizeCategory = true
        badge.accessibilityLabel = "Sponsored"

        media.contentMode = .scaleAspectFill
        media.clipsToBounds = true

        headline.font = Self.font(.semilight, 20, .title3)
        headline.numberOfLines = 3
        bodyText.font = Self.font(.regular, 14, .caption1)
        bodyText.numberOfLines = 2
        advertiser.font = Self.font(.regular, 14, .caption1)
        advertiser.numberOfLines = 1
        for label in [headline, bodyText, advertiser] {
            label.adjustsFontForContentSizeCategory = true
        }

        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true

        // Google handles the tap, so the button only has to look like one.
        action.font = Self.font(.semilight, 17, .body)
        action.adjustsFontForContentSizeCategory = true
        action.layer.borderWidth = 2
        action.setContentCompressionResistancePriority(.required, for: .horizontal)

        for view in [icon, advertiser, UIView(), action] {
            footer.addArrangedSubview(view)
        }
        footer.axis = .horizontal
        footer.spacing = 10
        footer.alignment = .center
        // Google rejects an asset that touches the ad view's edge by a rounding error, so the button stays a point in.
        footer.isLayoutMarginsRelativeArrangement = true
        footer.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 1, trailing: 1)

        for view in [badge, media, headline, bodyText, footer] {
            stack.addArrangedSubview(view)
        }
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(12, after: media)
        stack.setCustomSpacing(14, after: bodyText)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
        ])
        advertiser.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headlineView = headline
        bodyView = bodyText
        iconView = icon
        advertiserView = advertiser
        callToActionView = action
        mediaView = media
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ ad: NativeAd, palette: MetroPalette) {
        if shownPalette != palette {
            shownPalette = palette
            let foreground = UIColor(palette.foreground)
            badge.textColor = UIColor(palette.accentColor)
            headline.textColor = foreground
            // Brighter than the usual secondary text, so it reads over the hub's photo.
            bodyText.textColor = foreground.withAlphaComponent(0.75)
            advertiser.textColor = foreground.withAlphaComponent(0.75)
            action.layer.borderColor = foreground.cgColor
            action.textColor = foreground
        }
        guard shownAd !== ad else { return }
        shownAd = ad

        headline.text = ad.headline
        bodyText.text = ad.body
        bodyText.isHidden = ad.body == nil
        advertiser.text = ad.advertiser
        advertiser.isHidden = ad.advertiser == nil
        icon.image = ad.icon?.image
        icon.isHidden = ad.icon?.image == nil
        action.text = ad.callToAction?.lowercased()
        action.isHidden = ad.callToAction == nil

        media.mediaContent = ad.mediaContent
        let ratio = ad.mediaContent.aspectRatio > 0 ? ad.mediaContent.aspectRatio : 16 / 9
        mediaRatio?.isActive = false
        mediaRatio = media.heightAnchor.constraint(equalTo: media.widthAnchor, multiplier: 1 / ratio)
        mediaRatio?.isActive = true

        pendingAd = ad
        setNeedsLayout()
    }

    /// Multi-line labels measure as one line unless they're told their width first.
    func fittingHeight(for width: CGFloat) -> CGFloat {
        headline.preferredMaxLayoutWidth = width
        bodyText.preferredMaxLayoutWidth = width
        return systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let pendingAd, bounds.width > 0, bounds.height > 0 else { return }
        self.pendingAd = nil
        // The stack sizes its children after this pass; Google measures them when the ad is set.
        stack.layoutIfNeeded()
        footer.layoutIfNeeded()
        // Registers the views above with Google, so set last.
        nativeAd = pendingAd
    }

    private static func font(_ weight: MetroWeight, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: weight.rawValue, size: size) ?? .systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

/// The call-to-action, drawn as an outlined Metro button.
final class InsetLabel: UILabel {
    private let insets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
