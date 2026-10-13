import AuthenticationServices
import SwiftData
import SwiftUI
#if SWIFT_PACKAGE
import BoardCore
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private enum OnboardingStep: Int {
    case welcome
    case signIn
    case focus
    case outcome
}

private enum OnboardingFocus: String, CaseIterable, Identifiable {
    case personal
    case work
    case learning
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal projects"
        case .work: "Work projects"
        case .learning: "Learning and skills"
        case .mixed: "A mix of everything"
        }
    }

    var subtitle: String {
        switch self {
        case .personal: "Creative ideas, home projects, and life goals"
        case .work: "Deliverables, launches, and professional goals"
        case .learning: "Courses, practice plans, and new skills"
        case .mixed: "One workspace for every part of your life"
        }
    }

    var icon: String {
        switch self {
        case .personal: "person.fill"
        case .work: "briefcase.fill"
        case .learning: "book.closed.fill"
        case .mixed: "square.grid.2x2.fill"
        }
    }
}

private enum OnboardingOutcome: String, CaseIterable, Identifiable {
    case priorities
    case followThrough
    case deadlines
    case blockers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .priorities: "Choose what matters next"
        case .followThrough: "Finish more of what I start"
        case .deadlines: "Stay ahead of deadlines"
        case .blockers: "See what needs attention"
        }
    }

    var subtitle: String {
        switch self {
        case .priorities: "Keep the next useful task easy to find"
        case .followThrough: "Turn ideas into steady visible progress"
        case .deadlines: "See time-sensitive work before it is urgent"
        case .blockers: "Make stalled tasks clear at a glance"
        }
    }

    var icon: String {
        switch self {
        case .priorities: "scope"
        case .followThrough: "checkmark.circle.fill"
        case .deadlines: "calendar.badge.clock"
        case .blockers: "exclamationmark.octagon.fill"
        }
    }
}

struct OnboardingFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardAppearance) private var appearance
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var context
    @Query private var profiles: [AppProfile]

    @State private var step: OnboardingStep = .welcome
    @State private var focus: OnboardingFocus?
    @State private var outcome: OnboardingOutcome?
    @State private var appleUserIdentifier: String?
    @State private var displayName: String?
    @State private var signInError: String?
    @State private var saveError: String?
    @AppStorage("appleSessionActive") private var appleSessionActive = false

    var body: some View {
        ZStack {
            onboardingBackground.ignoresSafeArea()
            Group {
                switch step {
                case .welcome: welcomeScreen
                case .signIn: signInScreen
                case .focus: focusScreen
                case .outcome: outcomeScreen
                }
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            ))
        }
        .font(AppTypography.body)
        .task(id: step) {
            guard step == .welcome else { return }
            try? await Task.sleep(nanoseconds: reduceMotion ? 350_000_000 : 1_150_000_000)
            guard !Task.isCancelled, step == .welcome else { return }
            move(to: .signIn)
        }
        .alert("Couldn’t finish setup", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var onboardingBackground: some View {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private var welcomeScreen: some View {
        VStack(spacing: 28) {
            Spacer()
            WorkspaceMark(size: 118)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Welcome to Tierin")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("A clear place for every idea, next step, and finished project.")
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            }
            Spacer()
            ProgressView()
                .controlSize(.small)
                .tint(appearance.accent.color)
                .accessibilityLabel("Opening setup")
        }
    }

    private var signInScreen: some View {
        VStack(spacing: 28) {
            Spacer()
            WorkspaceMark(size: 92)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Your workspace, on every device")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Sign in with Apple to connect your profile. Your projects stay private and sync through your iCloud account.")
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }
            Spacer()
            VStack(spacing: 14) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: 420)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHint("Uses your Apple Account to create or restore your workspace profile")

                if let signInError {
                    Text(signInError)
                        .font(AppTypography.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Label("Start free. No password to remember.", systemImage: "lock.shield.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var focusScreen: some View {
        questionScreen(
            number: 1,
            title: "What will you manage most?",
            subtitle: "This helps shape future starter projects and workspace insights.",
            canContinue: focus != nil,
            back: { move(to: .signIn) },
            next: { move(to: .outcome) }
        ) {
            ForEach(OnboardingFocus.allCases) { option in
                optionCard(
                    title: option.title,
                    subtitle: option.subtitle,
                    icon: option.icon,
                    selected: focus == option
                ) { focus = option }
            }
        }
    }

    private var outcomeScreen: some View {
        questionScreen(
            number: 2,
            title: "What should your board help improve?",
            subtitle: "Pick the result that would make Tierin most useful to you.",
            canContinue: outcome != nil,
            back: { move(to: .focus) },
            next: finishOnboarding
        ) {
            ForEach(OnboardingOutcome.allCases) { option in
                optionCard(
                    title: option.title,
                    subtitle: option.subtitle,
                    icon: option.icon,
                    selected: outcome == option
                ) { outcome = option }
            }
        }
    }

    private func questionScreen<Options: View>(
        number: Int,
        title: String,
        subtitle: String,
        canContinue: Bool,
        back: @escaping () -> Void,
        next: @escaping () -> Void,
        @ViewBuilder options: () -> Options
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                }
                .appGlassButton(size: .medium, shape: .circle)
                .accessibilityLabel("Back")
                Spacer()
                Text("\(number) of 2")
                    .font(AppTypography.metadataEmphasis)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(AppTypography.supporting)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 12) {
                    options()
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            Button(action: next) {
                Label(number == 2 ? "Open Workspace" : "Continue", systemImage: "arrow.right")
            }
            .appGlassButton(size: .large, shape: .rectangle, accent: true)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .disabled(!canContinue)
        }
    }

    private func optionCard(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(AppTypography.controlIcon)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppTypography.itemTitle)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.controlIcon)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.45))
            }
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .appCardSurface(cornerRadius: 18)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInError = "Apple did not return an account credential. Please try again."
                return
            }
            appleUserIdentifier = credential.user
            let components = credential.fullName
            let formattedName = components.map(PersonNameComponentsFormatter().string(from:))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = formattedName?.isEmpty == false ? formattedName : AppProfile.current(in: profiles)?.displayName
            signInError = nil
            move(to: .focus)
        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled {
                return
            }
            signInError = error.localizedDescription
        }
    }

    private func finishOnboarding() {
        guard let appleUserIdentifier, let focus, let outcome else { return }
        let profile = AppProfile.current(in: profiles) ?? AppProfile(
            stageNames: appearance.stageNames,
            accent: appearance.accent
        )
        if profile.modelContext == nil { context.insert(profile) }
        profile.appleUserIdentifier = appleUserIdentifier
        if let displayName { profile.displayName = displayName }
        profile.onboardingFocusValue = focus.rawValue
        profile.onboardingOutcomeValue = outcome.rawValue
        profile.onboardingCompletedAt = Date()
        profile.updatedAt = Date()
        do {
            try StoreWriter.save(context)
            appleSessionActive = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func move(to newStep: OnboardingStep) {
        if reduceMotion {
            step = newStep
        } else {
            withAnimation(.easeInOut(duration: 0.34)) { step = newStep }
        }
    }
}
