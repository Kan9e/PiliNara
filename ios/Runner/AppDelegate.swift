import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.applicationSupportsShakeToEdit = false // Disable shake to undo
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PlayerVolumeObserver") {
      FlutterEventChannel(name: "pilinara/player/outputVolume", binaryMessenger: registrar.messenger())
        .setStreamHandler(PlayerVolumeObserver())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PipPlugin") {
      PipPlugin.register(with: registrar)
    }
  }
}

// A player view owns the observation. Playback owns the shared audio session.
private final class PlayerVolumeObserver: NSObject, FlutterStreamHandler {
  private var observation: NSKeyValueObservation?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
      guard let volume = change.newValue else { return }
      DispatchQueue.main.async { events(Double(volume)) }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observation = nil
    return nil
  }
}
