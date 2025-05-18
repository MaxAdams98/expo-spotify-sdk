package expo.modules.spotifysdk

import android.content.pm.PackageManager
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import com.spotify.sdk.android.auth.AuthorizationClient
import com.spotify.sdk.android.auth.AuthorizationRequest
import com.spotify.sdk.android.auth.AuthorizationResponse
import com.spotify.sdk.android.auth.app.SpotifyNativeAuthUtil
import expo.modules.kotlin.exception.Exceptions
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

import com.spotify.android.appremote.api.ConnectionParams
import com.spotify.android.appremote.api.Connector
import com.spotify.android.appremote.api.SpotifyAppRemote
import com.spotify.protocol.types.PlayerState
import com.spotify.protocol.types.Repeat

import okhttp3.OkHttpClient
import okhttp3.FormBody
import okhttp3.Request
import okhttp3.Callback
import okhttp3.Call
import okhttp3.Response

import java.io.IOException
import org.json.JSONObject

class SpotifyConfigOptions : Record {
  @Field
  val scopes: List<String> = emptyList()

  @Field
  val tokenSwapURL: String? = null

  @Field
  val tokenRefreshURL: String? = null
}

class PlaybackOptions : Record {
  @Field
  val position: Double? = null

  @Field
  val playlistIndex: Int? = null
}

class ExpoSpotifySDKModule : Module() {

  private val requestCode = 2095
  private var requestConfig: SpotifyConfigOptions? = null
  private var authPromise: Promise? = null
  private var appRemote: SpotifyAppRemote? = null
  private var accessToken: String? = null

  private val context
    get() = appContext.reactContext ?: throw Exceptions.ReactContextLost()
  private val currentActivity
    get() = appContext.currentActivity ?: throw Exceptions.MissingActivity()

  override fun definition() = ModuleDefinition {

    Name("ExpoSpotifySDK")

    Function("isAvailable") {
      return@Function SpotifyNativeAuthUtil.isSpotifyInstalled(context)
    }

    AsyncFunction("authenticateAsync") { config: SpotifyConfigOptions, promise: Promise ->
      try {
        val packageInfo =
          context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_META_DATA)
        val applicationInfo = packageInfo.applicationInfo
        val metaData = applicationInfo?.metaData
        val clientId = metaData?.getString("spotifyClientId")
        val redirectUri = metaData?.getString("spotifyRedirectUri")

        requestConfig = config

        if (clientId == null || redirectUri == null) {
          promise.reject(
            "ERR_EXPO_SPOTIFY_SDK",
            "Missing Spotify configuration in AndroidManifest.xml. Ensure SPOTIFY_CLIENT_ID and SPOTIFY_REDIRECT_URI are set.",
            null
          )
          return@AsyncFunction
        }

        val responseType = if (config.tokenSwapURL != null || config.tokenRefreshURL != null) {
          AuthorizationResponse.Type.CODE
        } else {
          AuthorizationResponse.Type.TOKEN
        }

        val request = AuthorizationRequest.Builder(
          clientId,
          responseType,
          redirectUri
        )
          .setScopes(config.scopes.toTypedArray())
          .build()

        authPromise = promise
        AuthorizationClient.openLoginActivity(currentActivity, requestCode, request)

      } catch (e: PackageManager.NameNotFoundException) {
        promise.reject(
          "ERR_EXPO_SPOTIFY_SDK",
          "Missing Spotify configuration in AndroidManifest.xml",
          e
        )
      }
    }

    // MARK: - Playback Methods

    // Connect App Remote
    private fun connectAppRemote(token: String, promise: Promise) {
      val packageInfo =
        context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_META_DATA)
      val applicationInfo = packageInfo.applicationInfo
      val metaData = applicationInfo?.metaData
      val clientId = metaData?.getString("spotifyClientId")
      val redirectUri = metaData?.getString("spotifyRedirectUri")

      if (clientId == null || redirectUri == null) {
        promise.reject(
          "ERR_EXPO_SPOTIFY_SDK",
          "Missing Spotify configuration in AndroidManifest.xml. Ensure SPOTIFY_CLIENT_ID and SPOTIFY_REDIRECT_URI are set.",
          null
        )
        return
      }

      // Connect to AppRemote if not already connected
      if (appRemote?.isConnected != true) {
        println("ExpoSpotifySDK: Connecting to Spotify App Remote with clientId: ${clientId.take(5)}*** and redirectUri: $redirectUri")

        val connectionParams = ConnectionParams.Builder(clientId)
          .setRedirectUri(redirectUri)
          .showAuthView(true)
          .build()

        SpotifyAppRemote.connect(context, connectionParams, object : Connector.ConnectionListener {
          override fun onConnected(spotifyAppRemote: SpotifyAppRemote) {
            println("ExpoSpotifySDK: Successfully connected to Spotify App Remote")
            appRemote = spotifyAppRemote
            accessToken = token
            promise.resolve(true)
          }

          override fun onFailure(error: Throwable) {
            println("ExpoSpotifySDK: Failed to connect to Spotify App Remote. Error: ${error.message}, Class: ${error.javaClass.name}")
            error.printStackTrace()

            val errorMessage = when {
              error.message?.contains("AUTHENTICATION_FAILED") == true ->
                "Authentication failed. Please check your Spotify credentials or re-authenticate."
              error.message?.contains("NOT_INSTALLED") == true ->
                "Spotify app is not installed or needs to be updated."
              error.message?.contains("SPOTIFY_APP_REMOTE") == true ->
                "Problem with Spotify App Remote. Please restart the Spotify app."
              else -> "Failed to connect to Spotify: ${error.message}"
            }

            promise.reject("ERR_EXPO_SPOTIFY_SDK", errorMessage, error)
          }
        })
      } else {
        // Already connected
        println("ExpoSpotifySDK: Already connected to Spotify App Remote")
        promise.resolve(true)
      }
    }

    // Play a track URI
    AsyncFunction("playTrack") { uri: String, options: PlaybackOptions?, promise: Promise ->
      if (appRemote?.isConnected != true) {
        println("ExpoSpotifySDK: playTrack called but not connected to App Remote")

        // If we've failed connection recently, don't try repeatedly
        if (accessToken != null) {
          println("ExpoSpotifySDK: Attempting to reconnect using existing token")
          connectAppRemote(accessToken!!, object : Promise {
            override fun resolve(value: Any?) {
              if (value == true) {
                playTrackInternal(uri, options, promise)
              } else {
                promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to connect to Spotify App Remote", null)
              }
            }

            override fun reject(code: String, message: String?, e: Throwable?) {
              // If we can't connect, just report the error without trying again
              println("ExpoSpotifySDK: Reconnection failed: $message")
              promise.reject("ERR_EXPO_SPOTIFY_SDK", "Spotify connection failed: $message", e)
            }
          })
        } else {
          println("ExpoSpotifySDK: No access token available for reconnection")
          promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify and no token available", null)
        }
      } else {
        println("ExpoSpotifySDK: playTrack with uri: ${uri.take(20)}...")
        playTrackInternal(uri, options, promise)
      }
    }

    private fun playTrackInternal(uri: String, options: PlaybackOptions?, promise: Promise) {
      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        val positionMs = options?.position?.toLong() ?: 0L

        playerApi.play(uri)
          .setResultCallback {
            if (positionMs > 0) {
              playerApi.seekTo(positionMs)
                .setResultCallback {
                  promise.resolve(true)
                }
                .setErrorCallback { error ->
                  promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to seek", error)
                }
            } else {
              promise.resolve(true)
            }
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to play track", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Play a playlist
    AsyncFunction("playPlaylist") { uri: String, options: PlaybackOptions?, promise: Promise ->
      if (appRemote?.isConnected != true) {
        if (accessToken != null) {
          connectAppRemote(accessToken!!, object : Promise {
            override fun resolve(value: Any?) {
              if (value == true) {
                playContextInternal(uri, options, promise)
              } else {
                promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to connect to Spotify App Remote", null)
              }
            }

            override fun reject(code: String, message: String?, e: Throwable?) {
              promise.reject(code, message, e)
            }
          })
        } else {
          promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        }
      } else {
        playContextInternal(uri, options, promise)
      }
    }

    // Play an album
    AsyncFunction("playAlbum") { uri: String, options: PlaybackOptions?, promise: Promise ->
      if (appRemote?.isConnected != true) {
        if (accessToken != null) {
          connectAppRemote(accessToken!!, object : Promise {
            override fun resolve(value: Any?) {
              if (value == true) {
                playContextInternal(uri, options, promise)
              } else {
                promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to connect to Spotify App Remote", null)
              }
            }

            override fun reject(code: String, message: String?, e: Throwable?) {
              promise.reject(code, message, e)
            }
          })
        } else {
          promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        }
      } else {
        playContextInternal(uri, options, promise)
      }
    }

    private fun playContextInternal(uri: String, options: PlaybackOptions?, promise: Promise) {
      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        val positionMs = options?.position?.toLong() ?: 0L
        val index = options?.playlistIndex ?: 0

        playerApi.play(uri)
          .setResultCallback {
            // Handle position and index if needed
            if (index > 0) {
              playerApi.skipToIndex(uri, index)
                .setResultCallback {
                  if (positionMs > 0) {
                    playerApi.seekTo(positionMs)
                      .setResultCallback {
                        promise.resolve(true)
                      }
                      .setErrorCallback { error ->
                        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to seek", error)
                      }
                  } else {
                    promise.resolve(true)
                  }
                }
                .setErrorCallback { error ->
                  promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to skip to index", error)
                }
            } else if (positionMs > 0) {
              playerApi.seekTo(positionMs)
                .setResultCallback {
                  promise.resolve(true)
                }
                .setErrorCallback { error ->
                  promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to seek", error)
                }
            } else {
              promise.resolve(true)
            }
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to play context", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Pause
    AsyncFunction("pausePlayback") { promise: Promise ->
      if (appRemote?.isConnected != true) {
        println("ExpoSpotifySDK: pausePlayback called but not connected to App Remote")
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      println("ExpoSpotifySDK: Pausing playback")
      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        playerApi.pause()
          .setResultCallback {
            println("ExpoSpotifySDK: Playback paused successfully")
            promise.resolve(true)
          }
          .setErrorCallback { error ->
            println("ExpoSpotifySDK: Failed to pause: ${error.message}")
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to pause", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Resume
    AsyncFunction("resumePlayback") { promise: Promise ->
      if (appRemote?.isConnected != true) {
        println("ExpoSpotifySDK: resumePlayback called but not connected to App Remote")
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      println("ExpoSpotifySDK: Resuming playback")
      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        playerApi.resume()
          .setResultCallback {
            println("ExpoSpotifySDK: Playback resumed successfully")
            promise.resolve(true)
          }
          .setErrorCallback { error ->
            println("ExpoSpotifySDK: Failed to resume: ${error.message}")
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to resume", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Skip to next track
    AsyncFunction("skipToNext") { promise: Promise ->
      if (appRemote?.isConnected != true) {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        playerApi.skipNext()
          .setResultCallback {
            promise.resolve(true)
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to skip to next", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Skip to previous track
    AsyncFunction("skipToPrevious") { promise: Promise ->
      if (appRemote?.isConnected != true) {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        playerApi.skipPrevious()
          .setResultCallback {
            promise.resolve(true)
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to skip to previous", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Seek to position
    AsyncFunction("seekToPosition") { positionMs: Double, promise: Promise ->
      if (appRemote?.isConnected != true) {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        playerApi.seekTo(positionMs.toLong())
          .setResultCallback {
            promise.resolve(true)
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to seek", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Set shuffle mode
    AsyncFunction("setShuffle") { enabled: Boolean, promise: Promise ->
      if (appRemote?.isConnected != true) {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        playerApi.setShuffle(enabled)
          .setResultCallback {
            promise.resolve(true)
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to set shuffle mode", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Set repeat mode
    AsyncFunction("setRepeatMode") { mode: String, promise: Promise ->
      if (appRemote?.isConnected != true) {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        val repeatMode = when (mode) {
          "track" -> Repeat.ONE
          "context" -> Repeat.ALL
          else -> Repeat.OFF
        }

        playerApi.setRepeat(repeatMode)
          .setResultCallback {
            promise.resolve(true)
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to set repeat mode", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Get current player state
    AsyncFunction("getPlayerState") { promise: Promise ->
      if (appRemote?.isConnected != true) {
        println("ExpoSpotifySDK: getPlayerState called but not connected to App Remote")
        // Instead of rejecting with an error, return a default state indicating we're not connected
        // This prevents repeated reconnection attempts just for state checking
        val defaultState = mapOf(
          "playing" to false,
          "track" to null,
          "playbackPosition" to 0,
          "playbackSpeed" to 1.0,
          "repeatMode" to "off",
          "shuffleModeEnabled" to false,
          "connected" to false // Add a field to indicate connection status
        )

        promise.resolve(defaultState)
        return@AsyncFunction
      }

      println("ExpoSpotifySDK: Getting player state")
      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        playerApi.playerState
          .setResultCallback { playerState ->
            println("ExpoSpotifySDK: Player state retrieved successfully")
            val track = playerState.track

            val trackMap = if (track != null) {
              val artistsArray = track.artists.map { artist ->
                mapOf(
                  "name" to artist.name,
                  "uri" to artist.uri
                )
              }

              val albumMap = track.album?.let { album ->
                val albumImages = if (album.coverArtImageURI != null) {
                  listOf(
                    mapOf(
                      "url" to album.coverArtImageURI.toString(),
                      "width" to 300,
                      "height" to 300
                    )
                  )
                } else {
                  emptyList<Map<String, Any>>()
                }

                mapOf(
                  "name" to album.name,
                  "uri" to album.uri,
                  "images" to albumImages
                )
              }

              val trackInfo = mutableMapOf(
                "uri" to track.uri,
                "name" to track.name,
                "duration" to track.duration,
                "artists" to artistsArray
              )

              if (albumMap != null) {
                trackInfo["album"] = albumMap
              }

              trackInfo
            } else null

            val repeatMode = when (playerState.playbackOptions.repeatMode) {
              Repeat.ONE -> "track"
              Repeat.ALL -> "context"
              else -> "off"
            }

            val state = mapOf(
              "playing" to !playerState.isPaused,
              "track" to trackMap,
              "playbackPosition" to playerState.playbackPosition,
              "playbackSpeed" to 1.0,
              "repeatMode" to repeatMode,
              "shuffleModeEnabled" to playerState.playbackOptions.isShuffling,
              "connected" to true // Add connection status
            )

            promise.resolve(state)
          }
          .setErrorCallback { error ->
            println("ExpoSpotifySDK: Failed to get player state: ${error.message}")
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to get player state", error)
          }
      } else {
        println("ExpoSpotifySDK: Player API not available")
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Set volume
    AsyncFunction("setVolume") { volume: Double, promise: Promise ->
      if (appRemote?.isConnected != true) {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        // Volume should be between 0 and 1
        val volumeValue = volume.coerceIn(0.0, 1.0).toFloat()

        playerApi.setVolume(volumeValue)
          .setResultCallback {
            promise.resolve(true)
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to set volume", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    // Get volume
    AsyncFunction("getVolume") { promise: Promise ->
      if (appRemote?.isConnected != true) {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Not connected to Spotify", null)
        return@AsyncFunction
      }

      val playerApi = appRemote?.playerApi
      if (playerApi != null) {
        playerApi.playerState
          .setResultCallback { playerState ->
            promise.resolve(playerState.playbackOptions.volume.toDouble())
          }
          .setErrorCallback { error ->
            promise.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to get volume", error)
          }
      } else {
        promise.reject("ERR_EXPO_SPOTIFY_SDK", "Player API not available", null)
      }
    }

    OnActivityResult { _, payload ->
      if (payload.requestCode == requestCode) {
        val authResponse = AuthorizationClient.getResponse(payload.resultCode, payload.data)

        when (authResponse.type) {
          AuthorizationResponse.Type.TOKEN -> {
            val expirationDate = System.currentTimeMillis() + authResponse.expiresIn * 1000
            accessToken = authResponse.accessToken

            authPromise?.resolve(
              mapOf(
                "accessToken" to authResponse.accessToken,
                "refreshToken" to null, // Spotify SDK does not return refresh token
                "expirationDate" to expirationDate,
                "scope" to requestConfig?.scopes
              )
            )
          }

          AuthorizationResponse.Type.CODE -> {
            val client = OkHttpClient()
            val requestBody = FormBody.Builder()
              .add("code", authResponse.code)
              .build()

            val request = Request.Builder()
              .url(requestConfig?.tokenSwapURL!!)
              .post(requestBody)
              .header("Content-Type", "application/x-www-form-urlencoded")
              .build()

            client.newCall(request).enqueue(object : Callback {
              override fun onFailure(call: Call, e: IOException) {
                authPromise?.reject("ERR_EXPO_SPOTIFY_SDK", e.message, e)
                authPromise = null
              }

              override fun onResponse(call: Call, response: Response) {
                if (!response.isSuccessful) {
                  authPromise?.reject("ERR_EXPO_SPOTIFY_SDK", "Failed to swap code for token", null)
                  authPromise = null
                  return
                }

                response.body?.string()?.let { body ->
                  val json = JSONObject(body)
                  val accessToken = json.getString("access_token")
                  val refreshToken = json.getString("refresh_token")
                  val expiresIn = json.getInt("expires_in")
                  val scope = json.getString("scope")
                  val expirationDate = System.currentTimeMillis() + expiresIn * 1000

                  this@ExpoSpotifySDKModule.accessToken = accessToken

                  authPromise?.resolve(
                    mapOf(
                      "accessToken" to accessToken,
                      "refreshToken" to refreshToken,
                      "expirationDate" to expirationDate,
                      "scope" to scope.split(' ')
                    )
                  )
                } ?: run {
                  authPromise?.reject("ERR_EXPO_SPOTIFY_SDK", "Empty response body", null)
                }
                authPromise = null
              }
            })
          }

          AuthorizationResponse.Type.ERROR -> {
            authPromise?.reject("ERR_EXPO_SPOTIFY_SDK", authResponse.error, null)
            authPromise = null
          }

          else -> {
            authPromise?.reject("ERR_EXPO_SPOTIFY_SDK", "Unknown response type", null)
            authPromise = null
          }
        }
      }
    }
  }
}
