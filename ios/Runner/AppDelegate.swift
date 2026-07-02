import Flutter
import UIKit
import FamilyControls
import ManagedSettings
import DeviceActivity

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var eventSink: FlutterEventSink?
  
  // Available from iOS 15+ Screen Time API
  @available(iOS 15.0, *)
  private lazy var settingsStore: ManagedSettingsStore = ManagedSettingsStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    // MethodChannel linking
    let methodChannel = FlutterMethodChannel(name: "com.habitbreaker.app/blocking",
                                              binaryMessenger: controller.binaryMessenger)
    
    methodChannel.setMethodCallHandler({
      [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      guard let self = self else { return }
      
      switch call.method {
      case "checkPermissions":
        // Query authorization status for ScreenTime access
        if #available(iOS 15.0, *) {
          let center = AuthorizationCenter.shared
          let isAuthorized = center.authorizationStatus == .approved
          
          var permissions: [String: Bool] = [:]
          permissions["accessibility"] = isAuthorized // Mapping screen access state
          permissions["vpn"] = isAuthorized          // Mapping network restriction state
          permissions["admin"] = isAuthorized        // Mapping uninstall protection state
          result(permissions)
        } else {
          // iOS 14 fallback
          result(["accessibility": true, "vpn": true, "admin": true])
        }
        
      case "requestPermissions":
        let type = (call.arguments as? [String: Any])?["type"] as? String ?? ""
        if #available(iOS 15.0, *) {
          let center = AuthorizationCenter.shared
          Task {
            do {
              try await center.requestAuthorization(for: .individual)
              result(true)
            } catch {
              result(false)
            }
          }
        } else {
          result(true)
        }
        
      case "startBlocking":
        if #available(iOS 15.0, *) {
          // Apply system web content filtering restrictions using ManagedSettingsStore
          let denyList = [
            "youtube.com",
            "instagram.com",
            "tiktok.com",
            "pornhub.com",
            "xvideos.com",
            "redtube.com"
          ]
          self.settingsStore.webFilter.deny = WebFilterSettings.FilterOnly.specified(
            denyList.map { WebFilterSettings.Site(url: URL(string: "https://\($0)")!) },
            categories: []
          )
          
          self.triggerMockBlockingEvent(message: "iOS ManagedSettings applied: specified web filter rules activated.")
          result(true)
        } else {
          result(true)
        }
        
      case "stopBlocking":
        if #available(iOS 15.0, *) {
          // Remove active restrictions
          self.settingsStore.webFilter.deny = nil
          self.triggerMockBlockingEvent(message: "iOS ManagedSettings cleared: specified web filters deactivated.")
          result(true)
        } else {
          result(true)
        }
        
      case "updateBlocklist":
        let domains = (call.arguments as? [String: Any])?["domains"] as? [String] ?? []
        if #available(iOS 15.0, *) {
          if !domains.isEmpty {
            self.settingsStore.webFilter.deny = WebFilterSettings.FilterOnly.specified(
              domains.compactMap { WebFilterSettings.Site(url: URL(string: "https://\($0)")!) },
              categories: []
            )
          } else {
            self.settingsStore.webFilter.deny = nil
          }
          self.triggerMockBlockingEvent(message: "iOS ManagedSettings list updated with \(domains.count) URLs.")
          result(true)
        } else {
          result(true)
        }
        
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    // EventChannel linking
    let eventChannel = FlutterEventChannel(name: "com.habitbreaker.app/blocking_events",
                                            binaryMessenger: controller.binaryMessenger)
    eventChannel.setStreamHandler(self)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func triggerMockBlockingEvent(message: String) {
    guard let eventSink = eventSink else { return }
    let event: [String: Any] = [
      "type": "native_log",
      "message": message,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000)
    ]
    eventSink(event)
  }
}

extension AppDelegate: FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    triggerMockBlockingEvent(message: "iOS Screen Time Engine bound to Event Channel.")
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }
}
