import 'package:flutter/material.dart';
import 'package:infinite_jukebox/home_screen.dart';
import 'package:just_audio_background/just_audio_background.dart';

Future<void> main() async {
  // Initialize background audio service
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ryanheise.bg_demo.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  runApp(const InfiniteJukeboxApp());
}

class InfiniteJukeboxApp extends StatelessWidget {
  const InfiniteJukeboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinite Jukebox Local',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
