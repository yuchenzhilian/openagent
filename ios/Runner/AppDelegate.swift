// AppDelegate.swift
// Integration template for OpenAgent iOS.
//
// After running `flutter create --platforms=ios .`, replace the generated
// ios/Runner/AppDelegate.swift with this file (or merge the key parts).
//
// This registers the IosAutomationChannel MethodChannel and handles
// NSUserActivity callbacks from Siri Shortcuts.

import Flutter
import UIKit
import ActivityKit

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as? FlutterViewController

        // Register the iOS automation MethodChannel
        if let controller = controller {
            IosAutomationChannel.register(with: controller.registrar(forPlugin: "IosAutomationChannel")!)
        }

        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Handle NSUserActivity from Siri Shortcuts
    override func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        // Check if this is a shortcut invocation
        if userActivity.activityType.hasPrefix("com.openagent.openagent.shortcut.") {
            // Forward the shortcut invocation to Flutter via a method channel
            let controller = window?.rootViewController as? FlutterViewController
            let channel = FlutterMethodChannel(
                name: "com.openagent.ios.automation",
                binaryMessenger: controller!.binaryMessenger
            )
            let shortcutId = userActivity.activityType
                .replacingOccurrences(of: "com.openagent.openagent.shortcut.", with: "")
            channel.invokeMethod("shortcut_invoked", arguments: [
                "id": shortcutId,
                "title": userActivity.title ?? "",
                "userInfo": userActivity.userInfo ?? [:],
            ])
            return true
        }
        return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
}
