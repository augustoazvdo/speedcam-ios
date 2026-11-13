import SwiftUI

/// First launch: explains each permission; no system prompt before "Continue" (AC-001).
struct OnboardingView: View {
    let viewModel: CameraViewModel
    @State private var requesting = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 56, weight: .semibold))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(L10n.welcomeTitle)
                        .font(.largeTitle.bold())
                    Text(L10n.welcomeBody)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(OnboardingItem.all) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.title3)
                                    .frame(width: 32)
                                    .foregroundStyle(.red)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline)
                                    Text(item.reason).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            Button {
                requesting = true
                Task {
                    await viewModel.continueOnboarding()
                    requesting = false
                }
            } label: {
                Text(L10n.continueAction)
                    .font(.headline)
                    .frame(maxWidth: 480)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(requesting)
            .padding(24)
            .accessibilityIdentifier("onboarding.continue")
        }
        .background(Color.black.ignoresSafeArea())
    }
}
