import Combine
import Foundation
import Sparkle

struct UpdateConfiguration: Equatable {
    let feedURL: URL
    let publicKey: String

    static func load(from infoDictionary: [String: Any]) -> UpdateConfiguration? {
        guard
            let feedValue = infoDictionary["SUFeedURL"] as? String,
            let feedURL = URL(string: feedValue),
            feedURL.scheme?.lowercased() == "https",
            feedURL.host != nil,
            let publicKey = infoDictionary["SUPublicEDKey"] as? String,
            let decodedPublicKey = Data(base64Encoded: publicKey),
            decodedPublicKey.count == 32
        else {
            return nil
        }

        return UpdateConfiguration(feedURL: feedURL, publicKey: publicKey)
    }
}

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    let isConfigured: Bool

    private let updaterController: SPUStandardUpdaterController?
    private var canCheckForUpdatesSubscription: AnyCancellable?

    init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        guard UpdateConfiguration.load(from: infoDictionary) != nil else {
            isConfigured = false
            updaterController = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.sendsSystemProfile = false
        isConfigured = true
        updaterController = controller
        canCheckForUpdatesSubscription = controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updaterController?.checkForUpdates(nil)
    }
}
