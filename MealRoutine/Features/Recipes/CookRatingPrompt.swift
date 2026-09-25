import SwiftUI

/// Centered rating prompt. Replaces the system confirmation dialog, which anchored too high.
struct CookRatingPrompt: View {
    var currentRating: MealRating?
    var onSave: (MealRating, [FeedbackReason]) -> Void
    var onCancel: () -> Void

    @FocusState private var isTitleFocused: Bool
    @State private var selected: MealRating?
    @State private var reasons: Set<FeedbackReason> = []

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)

            promptContent
                .frame(maxWidth: 360)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
                .padding(.horizontal, 24)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape, onCancel)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            isTitleFocused = true
            if selected == nil { selected = currentRating }
        }
    }

    private var promptContent: some View {
        ScrollView {
            promptStack
        }
        .frame(maxHeight: 560)
    }

    private var promptStack: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Bu yemek nasıldı?")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .focused($isTitleFocused)
                    .accessibilityAddTraits(.isHeader)
                Text("Seçtiğin puan kaydedilir.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(MealRating.allCases) { rating in
                    ratingButton(rating)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("İstersen bir not ekle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                FlowLayout(spacing: 8) {
                    ForEach(FeedbackReason.allCases) { reason in
                        FilterChip(
                            title: reason.title,
                            isSelected: reasons.contains(reason),
                            hint: "İsteğe bağlı not"
                        ) {
                            if reasons.contains(reason) {
                                reasons.remove(reason)
                            } else {
                                reasons.insert(reason)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Kaydet") {
                guard let selected else { return }
                onSave(selected, FeedbackReason.allCases.filter { reasons.contains($0) })
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected == nil ? Theme.accent.opacity(0.35) : Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius, style: .continuous))
            .disabled(selected == nil)
            .accessibilityHint("Puanı ve seçili notları kaydeder")

            Button("Vazgeç", action: onCancel)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private func ratingButton(_ rating: MealRating) -> some View {
        let isCurrent = selected == rating
        return Button {
            selected = rating
        } label: {
            HStack(spacing: 12) {
                Image(systemName: rating.systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(rating.title)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isCurrent {
                    Text("Mevcut")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isCurrent ? Theme.accent.opacity(0.16) : Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isCurrent ? Theme.accent : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCurrent ? "\(rating.title), mevcut puan" : rating.title)
        .accessibilityHint("Bu puanı kaydet")
    }
}

/// Compact confirmation after the prompt has closed.
struct SavedRatingToast: View {
    var notice: SavedRatingNotice
    var onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.sage)
                    .accessibilityHidden(true)
                Text(notice.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 340)
            .background {
                ZStack {
                    Capsule().fill(Theme.card)
                    Capsule().fill(Theme.sage.opacity(0.18))
                }
            }
            .overlay {
                Capsule().strokeBorder(Theme.sage.opacity(0.7), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notice.message)
        .accessibilityHint("Kapatmak için dokun")
    }
}
