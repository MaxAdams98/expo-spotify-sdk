import {
  SpotifyConfig,
  SpotifySession,
  PlayerState,
  PlaybackOptions,
} from './ExpoSpotifySDK.types';
import ExpoSpotifySDKModule from './ExpoSpotifySDKModule';

function isAvailable(): boolean {
  return ExpoSpotifySDKModule.isAvailable();
}

function authenticateAsync(config: SpotifyConfig): Promise<SpotifySession> {
  if (!config.scopes || config.scopes?.length === 0) {
    throw new Error('scopes are required');
  }

  return ExpoSpotifySDKModule.authenticateAsync(config);
}

const Authenticate = {
  authenticateAsync,
};

// Player functions for controlling playback
const Player = {
  playTrack: (uri: string, options?: PlaybackOptions): Promise<boolean> =>
    ExpoSpotifySDKModule.playTrack(uri, options),

  playPlaylist: (uri: string, options?: PlaybackOptions): Promise<boolean> =>
    ExpoSpotifySDKModule.playPlaylist(uri, options),

  playAlbum: (uri: string, options?: PlaybackOptions): Promise<boolean> =>
    ExpoSpotifySDKModule.playAlbum(uri, options),

  pause: (): Promise<boolean> => ExpoSpotifySDKModule.pausePlayback(),

  resume: (): Promise<boolean> => ExpoSpotifySDKModule.resumePlayback(),

  skipToNext: (): Promise<boolean> => ExpoSpotifySDKModule.skipToNext(),

  skipToPrevious: (): Promise<boolean> => ExpoSpotifySDKModule.skipToPrevious(),

  seekToPosition: (positionMs: number): Promise<boolean> =>
    ExpoSpotifySDKModule.seekToPosition(positionMs),

  setShuffle: (enabled: boolean): Promise<boolean> =>
    ExpoSpotifySDKModule.setShuffle(enabled),

  setRepeatMode: (mode: 'off' | 'track' | 'context'): Promise<boolean> =>
    ExpoSpotifySDKModule.setRepeatMode(mode),

  getPlayerState: (): Promise<PlayerState> =>
    ExpoSpotifySDKModule.getPlayerState(),

  setVolume: (volume: number): Promise<boolean> =>
    ExpoSpotifySDKModule.setVolume(volume),

  getVolume: (): Promise<number> => ExpoSpotifySDKModule.getVolume(),
};

export { isAvailable, Authenticate, Player, PlayerState, PlaybackOptions };
