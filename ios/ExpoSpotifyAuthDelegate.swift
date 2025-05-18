import ExpoModulesCore
import SpotifyiOS

public class ExpoSpotifyAuthDelegate: ExpoAppDelegateSubscriber {
    private let sessionManager = ExpoSpotifySessionManager.shared

    public func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        print("ExpoSpotifySDK: Handling URL callback: \(url)")

        // First try to handle App Remote parameters
        if let parameters = sessionManager.appRemote?.authorizationParameters(from: url) {
            print("ExpoSpotifySDK: App Remote parameters: \(parameters)")
            if let access_token = parameters[SPTAppRemoteAccessTokenKey] {
                print("ExpoSpotifySDK: Setting new access token")
                sessionManager.appRemote?.connectionParameters.accessToken = access_token
                sessionManager.accessToken = access_token

                // Try to connect after setting the token
                DispatchQueue.main.async {
                    _ = self.sessionManager.connect()
                        .done {
                            print("ExpoSpotifySDK: Successfully connected after URL callback")
                        }
                        .catch { error in
                            print("ExpoSpotifySDK: Failed to connect after URL callback: \(error)")
                        }
                }
                return true
            } else if let error_description = parameters[SPTAppRemoteErrorDescriptionKey] {
                print("ExpoSpotifySDK: App Remote error: \(error_description)")
                return false
            }
        }

        // Then try to handle authentication callback
        if let canHandleURL = sessionManager.sessionManager?.application(app, open: url, options: options) {
            print("ExpoSpotifySDK: Handled authentication callback")
            return canHandleURL
        }

        print("ExpoSpotifySDK: URL not handled by Spotify SDK")
        return false
    }
}
