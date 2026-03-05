import { registerRootComponent } from 'expo';
import TrackPlayer from 'react-native-track-player';
import App from './App';

registerRootComponent(App);

// Register the TrackPlayer playback service (background audio + notification controls)
TrackPlayer.registerPlaybackService(() => require('./service'));