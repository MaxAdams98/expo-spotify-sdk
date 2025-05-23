import { isAvailable } from 'expo-spotify-sdk';
import { useState } from 'react';
import { Alert, StyleSheet, Text, View } from 'react-native';

import { useSpotifyAuthentication } from './src/hooks/useSpotifyAuthentication';

export default function App() {
  const [authToken, setAuthToken] = useState('unknown');
  const { authenticateAsync } = useSpotifyAuthentication();

  async function handleAuthenticatePress() {
    try {
      setAuthToken('unknown');
      const session = await authenticateAsync({
        scopes: [
          'ugc-image-upload',
          'user-read-playback-state',
          'user-modify-playback-state',
          'user-read-currently-playing',
          'app-remote-control',
          'streaming',
          'playlist-read-private',
          'playlist-read-collaborative',
          'playlist-modify-private',
          'playlist-modify-public',
          'user-follow-modify',
          'user-follow-read',
          'user-top-read',
          'user-read-recently-played',
          'user-library-modify',
          'user-library-read',
          'user-read-email',
          'user-read-private',
        ],
      });

      setAuthToken(session.accessToken);
    } catch (error) {
      if (error instanceof Error) {
        Alert.alert('Error', error.message);
      }
    }
  }

  return (
    <View style={styles.container}>
      <Text onPress={handleAuthenticatePress}>Authenticate Me</Text>
      <Text>Spotify app is installed: {isAvailable() ? 'yes' : 'no'}</Text>
      <Text>Auth Token: {authToken}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
  },
});
