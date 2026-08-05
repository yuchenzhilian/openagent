// AppDelegate.swift
// OpenAgent iOS entry point.
//
// This file is automatically included by the Flutter-generated Xcode project.
// It registers the iOS automation MethodChannel and handles Siri Shortcuts
// callbacks.
//
// Channel: com.openagent.ios.automation
// Methods:
//   shortcut_donate   - Register a Siri Shortcut via NSUserActivity
//   shortcut_list     - List donated shortcuts
//   shortcut_trigger  - Open a URL scheme (tel:, sms:, maps:, etc.)
//   shortcut_delete   - Delete a donated shortcut
//   open_url          - Open a URL via UIApplication.shared.open
//   open_app          - Open an app via URL scheme
//   live_activity_start  - Start a Live Activity (ActivityKit)
//   live_activity_update - Update Live Activity content
//   live_activity_end    - End the Live Activity

import Flutter
import UIKit
import ActivityKit
import AppIntents

// MARK: - Live Activity attributes

@available(iOS 16.1, *)
struct AgentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var content: String
    }
    var agentId: String
}

// MARK: - iOS Automation Channel

@available(iOS 16.1, *)
class IosAutomationChannel: NSObject, FlutterPlugin {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.openagent.ios.automation",
            binaryMessenger: registrar.messenger()
        )
        let instance = IosAutomationChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private var currentActivity: Activity<AgentActivityAttributes>?

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "shortcut_donate":
            donateShortcut(
                id: args["id"] as? String ?? "",
                title: args["title"] as? String ?? "",
                description: args["description"] as? String ?? "",
                phrase: args["phrase"] as? String,
                result: result
            )
        case "shortcut_list":
            result([])
        case "shortcut_trigger":
            let url = args["url"] as? String ?? ""
            triggerUrl(url: url, result: result)
        case "shortcut_delete":
            let id = args["id"] as? String ?? ""
            NSUserActivity.deleteSavedUserActivities(withPersistentIdentifiers: [id]) {
                result(true)
            }
        case "open_url":
            let url = args["url"] as? String ?? ""
            openUrl(url: url, result: result)
        case "open_app":
            let scheme = args["scheme"] as? String ?? ""
            openUrl(url: scheme, result: result)
        case "live_activity_start":
            let title = args["title"] as? String ?? "Agent"
            let content = args["content"] as? String ?? ""
            startLiveActivity(title: title, content: content, result: result)
        case "live_activity_update":
            let content = args["content"] as? String ?? ""
            updateLiveActivity(content: content, result: result)
        case "live_activity_end":
            endLiveActivity(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Shortcuts

    private func donateShortcut(
        id: String, title: String, description: String,
        phrase: String?, result: @escaping FlutterResult
    ) {
        let activity = NSUserActivity(activityType: "com.openagent.openagent.shortcut.\(id)")
        activity.title = title
        activity.userInfo = ["id": id, "description": description]
        if let phrase = phrase { activity.suggestedInvocationPhrase = phrase }
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.persistentIdentifier = id
        activity.becomeCurrent()
        result(true)
    }

    private func triggerUrl(url: String, result: @escaping FlutterResult) {
        guard let urlObj = URL(string: url) else { result(false); return }
        DispatchQueue.main.async {
            UIApplication.shared.open(urlObj) { success in result(success) }
        }
    }

    // MARK: - URL / App opening

    private func openUrl(url: String, result: @escaping FlutterResult) {
        guard let urlObj = URL(string: url) else { result(false); return }
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(urlObj) {
                UIApplication.shared.open(urlObj) { success in result(success) }
            } else {
                result(false)
            }
        }
    }

    // MARK: - Live Activities

    private func startLiveActivity(title: String, content: String, result: @escaping FlutterResult) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { result(false); return }
        if currentActivity != nil { endLiveActivitySync() }
        let attributes = AgentActivityAttributes(agentId: "openagent")
        let state = AgentActivityAttributes.ContentState(title: title, content: content)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            currentActivity = activity
            result(true)
        } catch { result(false) }
    }

    private func updateLiveActivity(content: String, result: @escaping FlutterResult) {
        guard let activity = currentActivity else { result(false); return }
        let state = AgentActivityAttributes.ContentState(title: "Agent 运行中", content: content)
        Task {
            await activity.update(.init(state: state, staleDate: nil))
            result(true)
        }
    }

    private func endLiveActivity(result: @escaping FlutterResult) {
        guard let activity = currentActivity else { result(false); return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
            result(true)
        }
    }

    private func endLiveActivitySync() {
        guard let activity = currentActivity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        currentActivity = nil
    }
}

// MARK: - App Delegate

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as? FlutterViewController

        // Register the iOS automation MethodChannel
        if let controller = controller {
            IosAutomationChannel.register(
                with: controller.registrar(forPlugin: "IosAutomationChannel")!
            )
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
        if userActivity.activityType.hasPrefix("com.openagent.openagent.shortcut.") {
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
