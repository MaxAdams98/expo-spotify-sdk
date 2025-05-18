import Foundation
import SpotifyiOS

extension ExpoSpotifySessionManager: SPTSessionManagerDelegate {
    public func sessionManager(manager: SPTSessionManager, didInitiate session: SPTSession) {
        print("ExpoSpotifySDK: Session initiated successfully")
        self.currentSession = session

        // Connect to AppRemote immediately after successful authentication
        _ = connectAppRemote(with: session.accessToken)
            .done { _ in
                print("ExpoSpotifySDK: Successfully connected to AppRemote after authentication")
            }
            .catch { error in
                print("ExpoSpotifySDK: Failed to connect to AppRemote after authentication: \(error)")
            }

        authPromiseSeal?.fulfill(session)
        authPromiseSeal = nil
    }

    public func sessionManager(manager: SPTSessionManager, didFailWith error: Error) {
        print("ExpoSpotifySDK: Session manager failed with error: \(error.localizedDescription)")
        if let session = currentSession, connectionFailureCount < MAX_CONNECTION_FAILURES {
            print("ExpoSpotifySDK: Attempting to reconnect with existing session")
            connectionFailureCount += 1
            _ = connectAppRemote(with: session.accessToken)
        } else {
            print("ExpoSpotifySDK: Max connection failures reached or no session available")
            connectionFailureCount = 0
            authPromiseSeal?.reject(error)
        }
    }

    public func sessionManager(manager: SPTSessionManager, didRenew session: SPTSession) {
        print("ExpoSpotifySDK: Session was renewed")
        // Update the current session
        self.currentSession = session
    }
}

extension ExpoSpotifySessionManager: SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        print("ExpoSpotifySDK: App Remote connection established")
        isConnecting = false

        // Update connection state
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("ExpoSpotifySDK: Connection state updated - isConnected: \(appRemote.isConnected)")

            // Resolve any pending connection promise
            if let resolver = self.connectPromiseResolver {
                print("ExpoSpotifySDK: Resolving pending connection promise")
                resolver.fulfill(())
                self.connectPromiseResolver = nil
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        print("ExpoSpotifySDK: App Remote disconnected with error: \(error?.localizedDescription ?? "none")")
        isConnecting = false

        // Update connection state
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("ExpoSpotifySDK: Connection state updated - isConnected: \(appRemote.isConnected)")

            // Reject any pending connection promise
            if let resolver = self.connectPromiseResolver {
                print("ExpoSpotifySDK: Rejecting pending connection promise")
                resolver.reject(error ?? SessionManagerError.unknown)
                self.connectPromiseResolver = nil
            }

            // Attempt to reconnect if we have a valid session
            if let sessionManager = self.sessionManager,
               let session = sessionManager.session,
               !session.accessToken.isEmpty {
                print("ExpoSpotifySDK: Attempting to reconnect after disconnection")
                _ = self.connectAppRemote(with: session.accessToken)
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        print("ExpoSpotifySDK: App Remote connection attempt failed with error: \(error?.localizedDescription ?? "none")")

        // Check for specific error types
        if let error = error as NSError? {
            if error.domain == NSPOSIXErrorDomain && error.code == 61 {
                print("ExpoSpotifySDK: Connection refused - Spotify app may not be running")
                // Try to open Spotify app
                if let spotifyURL = URL(string: "spotify:") {
                    UIApplication.shared.open(spotifyURL) { success in
                        if success {
                            print("ExpoSpotifySDK: Opened Spotify app, will retry connection")
                            // Wait a moment for the app to launch
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                                guard let self = self else { return }
                                if let sessionManager = self.sessionManager,
                                   let session = sessionManager.session {
                                    _ = self.connectAppRemote(with: session.accessToken)
                                }
                            }
                        }
                    }
                }
            }
        }

        isConnecting = false

        // Update connection state
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("ExpoSpotifySDK: Connection state updated - isConnected: \(appRemote.isConnected)")

            // Reject any pending connection promise
            if let resolver = self.connectPromiseResolver {
                print("ExpoSpotifySDK: Rejecting pending connection promise")
                resolver.reject(error ?? SessionManagerError.unknown)
                self.connectPromiseResolver = nil
            }
        }
    }

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        print("ExpoSpotifySDK: Player state changed - Track: \(playerState.track.name)")

        // Only log state changes if we're actually connected
        if appRemote?.isConnected == true {
            print("ExpoSpotifySDK: Playback Info - " +
                  "isPaused: \(playerState.isPaused), " +
                  "position: \(playerState.playbackPosition), " +
                  "repeatMode: \(playerState.playbackOptions.repeatMode.rawValue), " +
                  "shuffle: \(playerState.playbackOptions.isShuffling)")
        }
    }
}

extension ExpoSpotifySessionManager {
    func applicationWillResignActive() {
        print("ExpoSpotifySDK: App will resign active")
        if let appRemote = appRemote, appRemote.isConnected {
            print("ExpoSpotifySDK: Disconnecting due to app resignation")
            appRemote.disconnect()
        }
    }

    func applicationDidBecomeActive() {
        print("ExpoSpotifySDK: App did become active")
        if let session = currentSession, !isConnected {
            print("ExpoSpotifySDK: Attempting to reconnect after app became active")
            // Add a small delay to ensure the app is fully active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                _ = self.connectAppRemote(with: session.accessToken)
                    .done {
                        print("ExpoSpotifySDK: Successfully reconnected after app became active")
                    }
                    .catch { error in
                        print("ExpoSpotifySDK: Failed to reconnect after app became active: \(error)")
                    }
            }
        } else {
            print("ExpoSpotifySDK: No reconnection needed - either already connected or no valid session")
        }
    }
}
