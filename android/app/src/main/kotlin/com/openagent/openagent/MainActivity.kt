package com.openagent.openagent

import com.openagent.openagent.automation.AutomationChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var automationChannel: AutomationChannel? = null
    private var deviceProbe: DeviceProbe? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        automationChannel = AutomationChannel(this).also { it.attach(flutterEngine) }
        deviceProbe = DeviceProbe(this).also { it.attach(flutterEngine) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        automationChannel?.detach()
        automationChannel = null
        deviceProbe?.detach()
        deviceProbe = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
