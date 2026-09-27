import Observation

enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case connect
    case access
    case finish

    var titleKey: String {
        switch self {
        case .welcome: "onboarding.welcome.title"
        case .connect: "onboarding.step.connect"
        case .access: "onboarding.step.access"
        case .finish: "onboarding.step.quota"
        }
    }
}

enum SlideDirection: Sendable {
    case forward
    case backward
}

@MainActor
@Observable
final class OnboardingViewModel {
    private(set) var currentStep: OnboardingStep = .welcome
    private(set) var direction: SlideDirection = .forward
    // Keeps the access step in the progress row after the user resolves every request,
    // so the indicator and Back navigation stay stable.
    private var hasShownAccessStep = false

    func visibleSteps(needsAccess: Bool) -> [OnboardingStep] {
        let showsAccess = needsAccess || hasShownAccessStep || currentStep == .access
        return OnboardingStep.allCases.filter { $0 != .access || showsAccess }
    }

    /// Steps shown in the progress indicator; the welcome page is an introduction, not a task.
    func progressSteps(needsAccess: Bool) -> [OnboardingStep] {
        visibleSteps(needsAccess: needsAccess).filter { $0 != .welcome }
    }

    func canGoBack(needsAccess: Bool) -> Bool {
        visibleSteps(needsAccess: needsAccess).first != currentStep
    }

    func goNext(needsAccess: Bool) {
        let steps = visibleSteps(needsAccess: needsAccess)
        guard let index = steps.firstIndex(of: currentStep), index + 1 < steps.count else { return }
        direction = .forward
        move(to: steps[index + 1])
    }

    func goBack(needsAccess: Bool) {
        let steps = visibleSteps(needsAccess: needsAccess)
        guard let index = steps.firstIndex(of: currentStep), index > 0 else { return }
        direction = .backward
        move(to: steps[index - 1])
    }

    private func move(to step: OnboardingStep) {
        if step == .access { hasShownAccessStep = true }
        currentStep = step
    }
}
