import { requireNativeModule } from 'expo-modules-core';
import { PlayerState, PlaybackOptions } from './ExpoSpotifySDK.types';

// It loads the native module object from the JSI or falls back to
// the bridge module (from NativeModulesProxy) if the remote debugger is on.
interface ExpoSpotifySDKInterface {
  isAvailable(): boolean;
  authenticateAsync(config: any): Promise<any>;

  // Playback methods
  playTrack(uri: string, options?: PlaybackOptions): Promise<boolean>;
  playPlaylist(uri: string, options?: PlaybackOptions): Promise<boolean>;
  playAlbum(uri: string, options?: PlaybackOptions): Promise<boolean>;
  pausePlayback(): Promise<boolean>;
  resumePlayback(): Promise<boolean>;
  skipToNext(): Promise<boolean>;
  skipToPrevious(): Promise<boolean>;
  seekToPosition(positionMs: number): Promise<boolean>;
  setShuffle(enabled: boolean): Promise<boolean>;
  setRepeatMode(mode: 'off' | 'track' | 'context'): Promise<boolean>;
  getPlayerState(): Promise<PlayerState>;

  // Volume control
  setVolume(volume: number): Promise<boolean>;
  getVolume(): Promise<number>;
}

export default requireNativeModule('ExpoSpotifySDK') as ExpoSpotifySDKInterface;
