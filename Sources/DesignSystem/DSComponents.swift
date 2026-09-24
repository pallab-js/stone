import SwiftUI

struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(DS.Font.pageTitle)
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardContainer<Content: View>: View {
    var padding: CGFloat = DS.Spacing.lg
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.standard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.standard, style: .continuous)
                    .stroke(DS.Color.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

struct KPIValueCard: View {
    let title: String
    let value: String
    var footnote: String? = nil
    let icon: String
    var tint: SwiftUI.Color = DS.Color.info

    var body: some View {
        CardContainer {
            HStack(alignment: .top, spacing: DS.Spacing.m) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(tint))
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(title)
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(value)
                        .font(DS.Font.kpiValue)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let footnote {
                        Text(footnote)
                            .font(DS.Font.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct Badge: View {
    let text: String
    var tint: SwiftUI.Color = DS.Color.info

    var body: some View {
        Text(text)
            .font(DS.Font.footnote)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

struct SectionHeading: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            Text(title.uppercased())
                .font(DS.Font.groupLabel)
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(DS.Font.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(DS.Color.hairline)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.top, DS.Spacing.xs)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(DS.Color.accent.opacity(0.7))
            Text(title)
                .font(DS.Font.sectionTitle)
            if let message {
                Text(message)
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.Spacing.xxl)
    }
}

/// Compact empty state for use inside cards or scrolled sections where
/// `EmptyStateView`'s `.frame(maxHeight: .infinity)` would expand unbounded.
struct InlineEmptyState: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DS.Color.accent.opacity(0.6))
            Text(title)
                .font(DS.Font.bodySemibold)
                .foregroundStyle(.secondary)
            if let message {
                Text(message)
                    .font(DS.Font.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.xl)
    }
}

struct PhasePlaceholderView: View {
    let module: String
    let phase: String
    let description: String

    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            PageHeader(title: module, subtitle: "Planned under \(phase)")
                .frame(maxWidth: .infinity, alignment: .leading)
            EmptyStateView(
                icon: "square.stack.3d.up",
                title: "\(module) module incoming",
                message: description
            )
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.Color.contentBackground)
    }
}

struct ConfirmDialogModifier: ViewModifier {
    let title: String
    let message: String
    let destructiveLabel: String
    let isPresented: Binding<Bool>
    let action: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button(destructiveLabel, role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

extension View {
    func destructiveConfirmation(
        title: String,
        message: String,
        destructiveLabel: String,
        isPresented: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            ConfirmDialogModifier(
                title: title,
                message: message,
                destructiveLabel: destructiveLabel,
                isPresented: isPresented,
                action: action
            )
        )
    }

    /// Covers the view with an opaque background and spinner while data loads,
    /// so an empty state or zeroed KPIs never flash on first appearance.
    func loadingOverlay(_ isLoading: Bool) -> some View {
        overlay {
            if isLoading {
                ZStack {
                    DS.Color.contentBackground
                    ProgressView()
                        .controlSize(.large)
                }
                .ignoresSafeArea()
            }
        }
    }
}