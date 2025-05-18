import ExpoModulesCore
import SpotifyiOS

public class ExpoSpotifySDKModule: Module {

    public func definition() -> ModuleDefinition {

        let spotifySession = ExpoSpotifySessionManager.shared

        Name("ExpoSpotifySDK")

        Function("isAvailable") {
            let isInstalled = spotifySession.spotifyAppInstalled()
            print("ExpoSpotifySDK: Spotify app installation check: \(isInstalled ? "Installed" : "Not installed")")
            return isInstalled
        }

        AsyncFunction("authenticateAsync") { (config: [String: Any], promise: Promise) in
            guard let scopes = config["scopes"] as? [String] else {
                print("ExpoSpotifySDK: Invalid config - missing scopes")
                promise.reject("INVALID_CONFIG", "Invalid SpotifyConfig object")
                return
            }

            let tokenSwapURL = config["tokenSwapURL"] as? String
            let tokenRefreshURL = config["tokenRefreshURL"] as? String

            print("ExpoSpotifySDK: Authenticating with scopes: \(scopes.joined(separator: ", "))")
            print("ExpoSpotifySDK: Current session state - isConnected: \(spotifySession.isConnected), isAuthorized: \(spotifySession.isAuthorized)")

            spotifySession.authenticate(scopes: scopes, tokenSwapURL: tokenSwapURL, tokenRefreshURL: tokenRefreshURL).done { session in
                print("ExpoSpotifySDK: Authentication successful, token expires: \(session.expirationDate)")
                print("ExpoSpotifySDK: Post-auth session state - isConnected: \(spotifySession.isConnected), isAuthorized: \(spotifySession.isAuthorized)")
                promise.resolve([
                    "accessToken": session.accessToken,
                    "refreshToken": session.refreshToken,
                    "expirationDate": Int(session.expirationDate.timeIntervalSince1970 * 1000),
                    "scopes": SPTScopeSerializer.serializeScopes(session.scope)
                ])
            }.catch { error in
                print("ExpoSpotifySDK: Authentication failed: \(error.localizedDescription)")
                print("ExpoSpotifySDK: Failed auth session state - isConnected: \(spotifySession.isConnected), isAuthorized: \(spotifySession.isAuthorized)")
                promise.reject(error)
            }
        }

        // Playback Methods

        AsyncFunction("playTrack") { (uri: String, options: [String: Any]?, promise: Promise) in
            let position = options?["position"] as? Double ?? 0

            print("ExpoSpotifySDK: Playing track with URI: \(uri), position: \(position)")

            spotifySession.playSpotifyURI(uri, startingWith: position).done { _ in
                print("ExpoSpotifySDK: Track playback started successfully")
                promise.resolve(true)
            }.catch { error in
                print("ExpoSpotifySDK: Failed to play track: \(error.localizedDescription)")
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("playPlaylist") { (uri: String, options: [String: Any]?, promise: Promise) in
            let position = options?["position"] as? Double ?? 0
            let index = options?["playlistIndex"] as? Int ?? 0

            spotifySession.playSpotifyURI(uri, startingWith: position, startingIndex: index).done { _ in
                promise.resolve(true)
            }.catch { error in
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("playAlbum") { (uri: String, options: [String: Any]?, promise: Promise) in
            let position = options?["position"] as? Double ?? 0
            let index = options?["playlistIndex"] as? Int ?? 0

            spotifySession.playSpotifyURI(uri, startingWith: position, startingIndex: index).done { _ in
                promise.resolve(true)
            }.catch { error in
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("pausePlayback") { (promise: Promise) in
            print("ExpoSpotifySDK: Pausing playback")

            spotifySession.pausePlayback().done { _ in
                print("ExpoSpotifySDK: Playback paused successfully")
                promise.resolve(true)
            }.catch { error in
                print("ExpoSpotifySDK: Failed to pause playback: \(error.localizedDescription)")
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("resumePlayback") { (promise: Promise) in
            print("ExpoSpotifySDK: Resuming playback")

            spotifySession.resumePlayback().done { _ in
                print("ExpoSpotifySDK: Playback resumed successfully")
                promise.resolve(true)
            }.catch { error in
                print("ExpoSpotifySDK: Failed to resume playback: \(error.localizedDescription)")
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("skipToNext") { (promise: Promise) in
            spotifySession.skipToNext().done { _ in
                promise.resolve(true)
            }.catch { error in
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("skipToPrevious") { (promise: Promise) in
            spotifySession.skipToPrevious().done { _ in
                promise.resolve(true)
            }.catch { error in
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("seekToPosition") { (positionMs: Double, promise: Promise) in
            spotifySession.seekToPosition(positionMs).done { _ in
                promise.resolve(true)
            }.catch { error in
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("setShuffle") { (enabled: Bool, promise: Promise) in
            spotifySession.setShuffle(enabled).done { _ in
                promise.resolve(true)
            }.catch { error in
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("setRepeatMode") { (mode: String, promise: Promise) in
            spotifySession.setRepeatMode(mode).done { _ in
                promise.resolve(true)
            }.catch { error in
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("getPlayerState") { (promise: Promise) in
            print("ExpoSpotifySDK: Getting player state")

            // Add session state logging
            print("ExpoSpotifySDK: Session state - Present")
            print("ExpoSpotifySDK: Session details - isConnected: \(spotifySession.isConnected), isAuthorized: \(spotifySession.isAuthorized)")

            spotifySession.getPlayerState().done { state in
                print("ExpoSpotifySDK: Player state retrieved successfully")

                // Add connected flag to state
                var stateWithConnected = state
                stateWithConnected["connected"] = true

                promise.resolve(stateWithConnected)
            }.catch { error in
                print("ExpoSpotifySDK: Failed to get player state: \(error.localizedDescription)")

                // Instead of rejecting, return a default disconnected state
                if error is SessionManagerError {
                    print("ExpoSpotifySDK: Returning default disconnected state")
                    let defaultState: [String: Any] = [
                        "playing": false,
                        "track": NSNull(),
                        "playbackPosition": 0,
                        "playbackSpeed": 1.0,
                        "repeatMode": "off",
                        "shuffleModeEnabled": false,
                        "connected": false
                    ]
                    promise.resolve(defaultState)
                } else {
                    promise.reject(error)
                }
            }
        }

        AsyncFunction("setVolume") { (volume: Double, promise: Promise) in
            spotifySession.setVolume(volume).done { _ in
                promise.resolve(true)
            }.catch { error in
                promise.reject(error)
                promise.resolve(false)
            }
        }

        AsyncFunction("getVolume") { (promise: Promise) in
            spotifySession.getVolume().done { volume in
                promise.resolve(volume)
            }.catch { error in
                promise.reject(error)
            }
        }
    }
}
