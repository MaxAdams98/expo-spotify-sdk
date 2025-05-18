import ExpoModulesCore
import SpotifyiOS
import PromiseKit

// Extension to safely access imageIdentifier on SPTAppRemoteAlbum
extension SPTAppRemoteAlbum {
    var imageId: String? {
        // Unlike Track, Album may not always implement SPTAppRemoteImageRepresentable
        // so we need to check with a conditional cast
        if let imageRepresentable = self as? SPTAppRemoteImageRepresentable {
            return imageRepresentable.imageIdentifier
        }
        return nil
    }
}

// Extension to safely access imageIdentifier on SPTAppRemoteTrack
extension SPTAppRemoteTrack {
    var imageId: String? {
        // SPTAppRemoteTrack already conforms to SPTAppRemoteImageRepresentable
        return self.imageIdentifier
    }
}

// Extension to handle URI vs uri property
extension SPTAppRemoteTrack {
    var URI: String {
        // Forward to the lowercase version
        return self.uri
    }
}

extension SPTAppRemoteAlbum {
    var URI: String {
        // Forward to the lowercase version
        return self.uri
    }
}

extension SPTAppRemoteArtist {
    var URI: String {
        // Forward to the lowercase version
        return self.uri
    }
}

enum SessionManagerError: Error {
    case notInitialized
    case invalidConfiguration
    case spotifyAppNotInstalled
    case playerNotReady
    case methodNotAvailable
    case inCooldownPeriod
    case tooManyConnectionAttempts
    case connectionRefused
    case connectionTimeout
    case connectionInProgress
    case unknown
    case alreadyConnecting

    var localizedDescription: String {
        switch self {
        case .notInitialized:
            return "Spotify SDK not initialized"
        case .invalidConfiguration:
            return "Invalid Spotify configuration"
        case .spotifyAppNotInstalled:
            return "Spotify app is not installed"
        case .playerNotReady:
            return "Spotify player is not ready"
        case .methodNotAvailable:
            return "Method not available"
        case .inCooldownPeriod:
            return "Connection attempt in cooldown period"
        case .tooManyConnectionAttempts:
            return "Too many connection attempts"
        case .connectionRefused:
            return "Connection refused - Spotify app may not be running"
        case .connectionTimeout:
            return "Connection attempt timed out"
        case .connectionInProgress:
            return "Connection attempt already in progress"
        case .unknown:
            return "Unknown error"
        case .alreadyConnecting:
            return "Already connecting"
        }
    }
}

public final class ExpoSpotifySessionManager: NSObject {
    weak var module: ExpoSpotifySDKModule?
    var authPromiseSeal: Resolver<SPTSession>?
    public var accessToken: String?
    private var playURI: String = "" // Empty string to resume last played track
    var connectPromiseResolver: Resolver<Void>?
    var currentSession: SPTSession?

    // Add computed properties for connection state
    public var isConnected: Bool {
        return appRemote?.isConnected ?? false
    }

    public var isAuthorized: Bool {
        return currentSession != nil
    }

    // Connection management - changed from private to internal
    internal var lastConnectionAttempt: Date = Date.distantPast
    internal var connectionFailureCount: Int = 0
    internal let CONNECTION_COOLDOWN_SECONDS: TimeInterval = 5.0
    internal let MAX_CONNECTION_FAILURES: Int = 3

    // Add connection state tracking
    internal var isConnecting: Bool = false

    public static let shared = ExpoSpotifySessionManager()

    private var expoSpotifyConfiguration: ExpoSpotifyConfiguration? {
        guard let expoSpotifySdkDict = Bundle.main.object(forInfoDictionaryKey: "ExpoSpotifySDK") as? [String: String],
              let clientID = expoSpotifySdkDict["clientID"],
              let host = expoSpotifySdkDict["host"],
              let scheme = expoSpotifySdkDict["scheme"] else
        {
            return nil
        }

        return ExpoSpotifyConfiguration(clientID: clientID, host: host, scheme: scheme)
    }

    lazy var configuration: SPTConfiguration? = {
        guard let clientID = expoSpotifyConfiguration?.clientID,
              let redirectURL = expoSpotifyConfiguration?.redirectURL else {
            NSLog("Invalid Spotify configuration")
            return nil
        }

        print("ExpoSpotifySDK: Using redirectURL: \(redirectURL)")
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirectURL)
        configuration.playURI = self.playURI  // Initialize with empty play URI
        return configuration
    }()

    // Replace the current appRemote property with this lazy property
    public lazy var appRemote: SPTAppRemote? = {
        print("ExpoSpotifySDK: Initializing App Remote")
        print("ExpoSpotifySDK: Configuration state - \(configuration != nil ? "Present" : "Missing")")

        guard let configuration = self.configuration else {
            print("ExpoSpotifySDK: Failed to create configuration for App Remote")
            return nil
        }

        print("ExpoSpotifySDK: Configuration details:")
        print("  - Client ID: \(configuration.clientID)")
        print("  - Redirect URL: \(configuration.redirectURL.absoluteString)")
        print("  - Play URI: \(configuration.playURI ?? "nil")")

        let appRemote = SPTAppRemote(configuration: configuration, logLevel: .debug)
        print("ExpoSpotifySDK: Created App Remote instance")

        if let token = self.accessToken {
            print("ExpoSpotifySDK: Setting access token")
            appRemote.connectionParameters.accessToken = token
        } else {
            print("ExpoSpotifySDK: Warning - No access token available")
        }

        appRemote.delegate = self
        print("ExpoSpotifySDK: Set App Remote delegate")

        return appRemote
    }()

    lazy var sessionManager: SPTSessionManager? = {
        guard let configuration = configuration else {
            return nil
        }

        return SPTSessionManager(configuration: configuration, delegate: self)
    }()

    func authenticate(scopes: [String], tokenSwapURL: String?, tokenRefreshURL: String?) -> PromiseKit.Promise<SPTSession> {
        let (promise, seal) = PromiseKit.Promise<SPTSession>.pending()

        guard let clientID = self.expoSpotifyConfiguration?.clientID,
              let redirectURL = self.expoSpotifyConfiguration?.redirectURL else {
            NSLog("Invalid Spotify configuration")
            seal.reject(SessionManagerError.invalidConfiguration)
            return promise
        }

        // Reset connection failure count on authentication
        self.connectionFailureCount = 0
        print("ExpoSpotifySDK: Resetting connection failure count")

        let configuration = SPTConfiguration(clientID: clientID, redirectURL: redirectURL)

        if (tokenSwapURL != nil) {
            configuration.tokenSwapURL = URL(string: tokenSwapURL ?? "")
        }

        if (tokenRefreshURL != nil) {
            configuration.tokenRefreshURL = URL(string: tokenRefreshURL ?? "")
        }

        self.authPromiseSeal = seal
        self.configuration = configuration
        self.sessionManager = SPTSessionManager(configuration: configuration, delegate: self)

        DispatchQueue.main.sync {
            sessionManager?.initiateSession(with: SPTScopeSerializer.deserializeScopes(scopes), options: .default, campaign: nil)
        }

        return promise
    }

    func spotifyAppInstalled() -> Bool {
        guard let sessionManager = sessionManager else {
            print("ExpoSpotifySDK: SPTSessionManager not initialized")
            return false
        }

        var isInstalled = false
        DispatchQueue.main.sync {
            isInstalled = sessionManager.isSpotifyAppInstalled
        }
        print("ExpoSpotifySDK: Spotify app installed: \(isInstalled)")
        return isInstalled
    }

    // MARK: - Playback Methods

    func connect() -> PromiseKit.Promise<Void> {
        print("ExpoSpotifySDK: Attempting to connect to Spotify App Remote")
        print("ExpoSpotifySDK: Pre-connection session state - isConnected: \(isConnected), isAuthorized: \(isAuthorized)")

        return PromiseKit.Promise { seal in
            guard let appRemote = appRemote else {
                print("ExpoSpotifySDK: App Remote not initialized")
                seal.reject(SessionManagerError.notInitialized)
                return
            }

            // Check if Spotify app is installed
            guard spotifyAppInstalled() else {
                print("ExpoSpotifySDK: Spotify app is not installed")
                seal.reject(SessionManagerError.spotifyAppNotInstalled)
                return
            }

            // If already connected, just fulfill the promise
            if appRemote.isConnected {
                print("ExpoSpotifySDK: Already connected to Spotify App Remote")
                seal.fulfill(())
                return
            }

            // Check cooldown period
            let timeSinceLastAttempt = Date().timeIntervalSince(lastConnectionAttempt)
            if timeSinceLastAttempt < CONNECTION_COOLDOWN_SECONDS {
                print("ExpoSpotifySDK: In cooldown period, waiting \(CONNECTION_COOLDOWN_SECONDS - timeSinceLastAttempt) seconds")
                seal.reject(SessionManagerError.inCooldownPeriod)
                return
            }

            // Check connection failure count
            if connectionFailureCount >= MAX_CONNECTION_FAILURES {
                print("ExpoSpotifySDK: Too many connection failures")
                seal.reject(SessionManagerError.tooManyConnectionAttempts)
                return
            }

            // Update last connection attempt
            lastConnectionAttempt = Date()
            connectionFailureCount += 1

            // Store the resolver for later use
            self.connectPromiseResolver = seal

            // Ensure we have an access token
            guard let accessToken = self.accessToken else {
                print("ExpoSpotifySDK: No access token available")
                seal.reject(SessionManagerError.invalidConfiguration)
                return
            }

            // Set connection parameters
            appRemote.connectionParameters.accessToken = accessToken
            print("ExpoSpotifySDK: Setting up connection with access token")

            // Try to open Spotify app first if we're having connection issues
            if connectionFailureCount > 1 {
                print("ExpoSpotifySDK: Previous connection attempts failed, trying to open Spotify app first")
                openSpotifyApp()

                // Wait a moment for the app to open before connecting
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }
                    print("ExpoSpotifySDK: Initiating connection after opening Spotify app")
                    print("ExpoSpotifySDK: Access token before connect: \(appRemote.connectionParameters.accessToken ?? "nil")")
                    appRemote.connect()

                    // Set a timeout for the connection attempt
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                        guard let self = self else { return }
                        if !self.isConnected {
                            print("ExpoSpotifySDK: Connection attempt timed out")
                            self.connectPromiseResolver?.reject(SessionManagerError.connectionRefused)
                            self.connectPromiseResolver = nil
                        }
                    }
                }
            } else {
                // Connect with a longer timeout
                DispatchQueue.main.async {
                    print("ExpoSpotifySDK: Initiating connection on main thread")
                    print("ExpoSpotifySDK: Access token before connect: \(appRemote.connectionParameters.accessToken ?? "nil")")
                    appRemote.connect()

                    // Set a timeout for the connection attempt
                    DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                        guard let self = self else { return }
                        if !self.isConnected {
                            print("ExpoSpotifySDK: Connection attempt timed out")
                            self.connectPromiseResolver?.reject(SessionManagerError.connectionRefused)
                            self.connectPromiseResolver = nil
                        }
                    }
                }
            }
        }
    }

    func connectAppRemote(with accessToken: String) -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        // Reset connection state if we're in a bad state
        if isConnecting {
            print("ExpoSpotifySDK: Resetting connection state")
            isConnecting = false
        }

        guard !isConnecting else {
            print("ExpoSpotifySDK: Already connecting")
            seal.reject(SessionManagerError.alreadyConnecting)
            return promise
        }

        isConnecting = true

        print("ExpoSpotifySDK: Pre-connection session state - isConnected: \(appRemote?.isConnected ?? false), isAuthorized: \(currentSession != nil)")

        // Ensure we're on the main thread for UI operations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Set the access token
            self.accessToken = accessToken

            // Configure App Remote
            guard let configuration = self.configuration else {
                print("ExpoSpotifySDK: Configuration is nil")
                self.isConnecting = false
                seal.reject(SessionManagerError.invalidConfiguration)
                return
            }

            // Ensure appRemote is properly configured
            if let appRemote = self.appRemote {
                appRemote.connectionParameters.accessToken = accessToken
                print("ExpoSpotifySDK: Connecting to App Remote")
                print("ExpoSpotifySDK: Access token before connect: \(appRemote.connectionParameters.accessToken ?? "nil")")
                appRemote.connect()

                // Set up timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                    guard let self = self else { return }
                    if !(self.appRemote?.isConnected ?? false) {
                        print("ExpoSpotifySDK: Connection attempt timed out")
                        self.isConnecting = false
                        seal.reject(SessionManagerError.connectionTimeout)
                    }
                }
            } else {
                print("ExpoSpotifySDK: App Remote not initialized")
                self.isConnecting = false
                seal.reject(SessionManagerError.notInitialized)
            }
        }

        return promise
    }

    // Play a Spotify URI (track, album, playlist)
    func playSpotifyURI(_ uri: String, startingWith position: Double = 0, startingIndex: Int = 0) -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            if let session = sessionManager?.session {
                print("ExpoSpotifySDK: Not connected, attempting to connect before playing")
                // Try to connect first if we have a token
                connectAppRemote(with: session.accessToken).then { _ -> PromiseKit.Promise<Void> in
                    print("ExpoSpotifySDK: Connection successful, now playing URI")
                    return self.playSpotifyURI(uri, startingWith: position, startingIndex: startingIndex)
                }.done { _ in
                    seal.fulfill(())
                }.catch { error in
                    print("ExpoSpotifySDK: Failed to connect before playing: \(error.localizedDescription)")
                    seal.reject(error)
                }
                return promise
            }
            print("ExpoSpotifySDK: Player not ready and no session available")
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        // Check if URI is for a track, album, or playlist and handle accordingly
        if uri.contains("track") {
            // Play track
            appRemote.playerAPI?.play(uri, callback: { (success, error) in
                if let success = success as? Bool, success {
                    // If position is specified, seek to that position
                    if position > 0 {
                        appRemote.playerAPI?.seek(toPosition: Int(position), callback: { (seekSuccess, seekError) in
                            if let seekSuccess = seekSuccess as? Bool, seekSuccess {
                                seal.fulfill(())
                            } else if let seekError = seekError {
                                seal.reject(seekError)
                            } else {
                                seal.reject(SessionManagerError.playerNotReady)
                            }
                        })
                    } else {
                        seal.fulfill(())
                    }
                } else if let error = error {
                    seal.reject(error)
                } else {
                    seal.reject(SessionManagerError.playerNotReady)
                }
            })
        } else {
            // Play album or playlist
            appRemote.playerAPI?.play(uri, callback: { (success, error) in
                if let success = success as? Bool, success {
                    // If only position is specified, seek to that position
                    if position > 0 {
                        appRemote.playerAPI?.seek(toPosition: Int(position), callback: { (seekSuccess, seekError) in
                            if let seekSuccess = seekSuccess as? Bool, seekSuccess {
                                seal.fulfill(())
                            } else if let seekError = seekError {
                                seal.reject(seekError)
                            } else {
                                seal.reject(SessionManagerError.playerNotReady)
                            }
                        })
                    } else {
                        seal.fulfill(())
                    }
                } else if let error = error {
                    seal.reject(error)
                } else {
                    seal.reject(SessionManagerError.playerNotReady)
                }
            })
        }

        return promise
    }

    func pausePlayback() -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        appRemote.playerAPI?.pause({ (success, error) in
            if let success = success as? Bool, success {
                seal.fulfill(())
            } else if let error = error {
                seal.reject(error)
            } else {
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    func resumePlayback() -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        appRemote.playerAPI?.resume({ (success, error) in
            if let success = success as? Bool, success {
                seal.fulfill(())
            } else if let error = error {
                seal.reject(error)
            } else {
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    func skipToNext() -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        appRemote.playerAPI?.skip(toNext: { (success, error) in
            if let success = success as? Bool, success {
                seal.fulfill(())
            } else if let error = error {
                seal.reject(error)
            } else {
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    func skipToPrevious() -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        appRemote.playerAPI?.skip(toPrevious: { (success, error) in
            if let success = success as? Bool, success {
                seal.fulfill(())
            } else if let error = error {
                seal.reject(error)
            } else {
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    func seekToPosition(_ positionMs: Double) -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        appRemote.playerAPI?.seek(toPosition: Int(positionMs), callback: { (success, error) in
            if let success = success as? Bool, success {
                seal.fulfill(())
            } else if let error = error {
                seal.reject(error)
            } else {
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    func setShuffle(_ enabled: Bool) -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        appRemote.playerAPI?.setShuffle(enabled, callback: { (success, error) in
            if let success = success as? Bool, success {
                seal.fulfill(())
            } else if let error = error {
                seal.reject(error)
            } else {
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    func setRepeatMode(_ mode: String) -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        let repeatMode: SPTAppRemotePlaybackOptionsRepeatMode
        switch mode {
        case "track":
            repeatMode = .track
        case "context":
            repeatMode = .context
        default:
            repeatMode = .off
        }

        appRemote.playerAPI?.setRepeatMode(repeatMode, callback: { (success, error) in
            if let success = success as? Bool, success {
                seal.fulfill(())
            } else if let error = error {
                seal.reject(error)
            } else {
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    func getPlayerState() -> PromiseKit.Promise<[String: Any]> {
        let (promise, seal) = PromiseKit.Promise<[String: Any]>.pending()

        print("ExpoSpotifySDK: Getting player state")
        print("ExpoSpotifySDK: Session state - \(currentSession != nil ? "Present" : "Not Present")")
        print("ExpoSpotifySDK: Session details - isConnected: \(isConnected), isAuthorized: \(isAuthorized)")

        // If we're not connected but have a valid session, try to connect first
        if !isConnected, let session = currentSession {
            print("ExpoSpotifySDK: Not connected but have valid session, attempting to connect")
            connectAppRemote(with: session.accessToken)
                .then { _ -> PromiseKit.Promise<[String: Any]> in
                    print("ExpoSpotifySDK: Connection successful, now getting player state")
                    return self.getPlayerState()
                }
                .done { state in
                    seal.fulfill(state)
                }
                .catch { error in
                    print("ExpoSpotifySDK: Failed to connect before getting player state: \(error)")
                    seal.reject(error)
                }
            return promise
        }

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            print("ExpoSpotifySDK: Player not ready and no valid session available")
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        appRemote.playerAPI?.getPlayerState({ (playerState, error) in
            if let playerState = playerState as? SPTAppRemotePlayerState {
                var trackInfo: [String: Any]? = nil

                // According to the documentation, track is non-optional in the protocol
                let track = playerState.track
                // Only process if it's not an advertisement
                if !track.isAdvertisement {
                    var artistsArray: [[String: String]] = []
                    let artist = track.artist
                    artistsArray.append([
                        "name": artist.name,
                        "uri": artist.uri
                    ])

                    var albumInfo: [String: Any]? = nil
                    let album = track.album
                    var albumImages: [[String: Any]] = []
                    if let imageId = album.imageId {
                        albumImages.append([
                            "url": imageId,
                            "width": 300,
                            "height": 300
                        ])
                    }

                    albumInfo = [
                        "name": album.name,
                        "uri": album.uri,
                        "images": albumImages
                    ]

                    trackInfo = [
                        "uri": track.uri,
                        "name": track.name,
                        "duration": track.duration,
                        "artists": artistsArray
                    ]

                    if albumInfo != nil {
                        trackInfo?["album"] = albumInfo
                    }
                }

                var state: [String: Any] = [
                    "playing": playerState.isPaused == false,
                    "playbackPosition": playerState.playbackPosition,
                    "playbackSpeed": 1.0,
                    "repeatMode": self.getRepeatModeString(playerState.playbackOptions.repeatMode),
                    "shuffleModeEnabled": playerState.playbackOptions.isShuffling
                ]

                if let trackInfo = trackInfo {
                    state["track"] = trackInfo
                } else {
                    state["track"] = NSNull()
                }

                seal.fulfill(state)
            } else if let error = error {
                print("ExpoSpotifySDK: Error getting player state: \(error)")
                seal.reject(error)
            } else {
                print("ExpoSpotifySDK: Failed to get player state: Unknown error")
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    private func getRepeatModeString(_ mode: SPTAppRemotePlaybackOptionsRepeatMode) -> String {
        switch mode {
        case .track:
            return "track"
        case .context:
            return "context"
        default:
            return "off"
        }
    }

    func setVolume(_ volume: Double) -> PromiseKit.Promise<Void> {
        let (promise, seal) = PromiseKit.Promise<Void>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        // Volume should be between 0 and 1
        let _ = max(0, min(1, volume))

        // Set volume is not directly available in the public API
        // We'll try a different approach
        seal.reject(SessionManagerError.methodNotAvailable)
        return promise
    }

    func getVolume() -> PromiseKit.Promise<Double> {
        let (promise, seal) = PromiseKit.Promise<Double>.pending()

        guard let appRemote = self.appRemote, appRemote.isConnected else {
            seal.reject(SessionManagerError.playerNotReady)
            return promise
        }

        appRemote.playerAPI?.getPlayerState({ (playerState, error) in
            if let _ = playerState as? SPTAppRemotePlayerState {
                // Use a default volume since we can't easily access the volume
                seal.fulfill(1.0)
            } else if let error = error {
                seal.reject(error)
            } else {
                seal.reject(SessionManagerError.playerNotReady)
            }
        })

        return promise
    }

    // Add connection timeout handling
    private func handleConnectionTimeout() {
        print("ExpoSpotifySDK: Connection attempt timed out")
        connectPromiseResolver?.reject(SessionManagerError.playerNotReady)
        connectPromiseResolver = nil
    }

    // Add connection retry logic
    internal func retryConnection() {
        print("ExpoSpotifySDK: Retrying connection")
        connectionFailureCount += 1

        if connectionFailureCount >= MAX_CONNECTION_FAILURES {
            print("ExpoSpotifySDK: Max connection failures reached")
            connectPromiseResolver?.reject(SessionManagerError.tooManyConnectionAttempts)
            connectPromiseResolver = nil
            return
        }

        // Wait for cooldown period before retrying
        let timeSinceLastAttempt = Date().timeIntervalSince(lastConnectionAttempt)
        if timeSinceLastAttempt < CONNECTION_COOLDOWN_SECONDS {
            print("ExpoSpotifySDK: In cooldown period, waiting before retry")
            connectPromiseResolver?.reject(SessionManagerError.inCooldownPeriod)
            connectPromiseResolver = nil
            return
        }

        lastConnectionAttempt = Date()

        // Ensure we have a valid session before retrying
        guard let session = currentSession else {
            print("ExpoSpotifySDK: No valid session available for retry")
            connectPromiseResolver?.reject(SessionManagerError.notInitialized)
            connectPromiseResolver = nil
            return
        }

        // Ensure we're on the main thread for UI operations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            print("ExpoSpotifySDK: Attempting retry connection with session")
            _ = self.connectAppRemote(with: session.accessToken)
                .done { _ in
                    print("ExpoSpotifySDK: Retry connection successful")
                }
                .catch { error in
                    print("ExpoSpotifySDK: Retry connection failed: \(error)")
                    let nsError = error as NSError
                    if nsError.domain == NSPOSIXErrorDomain && nsError.code == 61 {
                        print("ExpoSpotifySDK: Connection refused - attempting to open Spotify app")
                        self.openSpotifyApp()

                        // Wait a moment for the app to open before retrying
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            print("ExpoSpotifySDK: Retrying connection after opening Spotify app")
                            _ = self.connectAppRemote(with: session.accessToken)
                                .done { _ in
                                    print("ExpoSpotifySDK: Connection successful after opening Spotify app")
                                }
                                .catch { error in
                                    print("ExpoSpotifySDK: Connection still failed after opening Spotify app: \(error)")
                                }
                        }
                    }
                }
        }
    }

    func disconnect() {
        print("ExpoSpotifySDK: Disconnecting from Spotify App Remote")
        print("ExpoSpotifySDK: Pre-disconnect session state - isConnected: \(isConnected), isAuthorized: \(isAuthorized)")

        if let appRemote = appRemote {
            if appRemote.isConnected {
                appRemote.disconnect()
                print("ExpoSpotifySDK: Disconnect called on App Remote")
            } else {
                print("ExpoSpotifySDK: App Remote already disconnected")
            }
        } else {
            print("ExpoSpotifySDK: No App Remote instance to disconnect")
        }
    }

    func openSpotifyApp() {
        guard let url = URL(string: "spotify://") else { return }
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
}
