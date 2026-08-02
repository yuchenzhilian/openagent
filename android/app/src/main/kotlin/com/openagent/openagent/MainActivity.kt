package com.openagent.openagent

import com.openagent.openagent.automation.AutomationChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var automationChannel: AutomationChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        automationChannel = AutomationChannel(this).also { it.attach(flutterEngine) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        automationChannel?.detach()
        automationChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
