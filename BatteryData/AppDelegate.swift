//
//  AppDelegate.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 17.12.2025.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let vm: BatteryViewModel
    private var statusBar: StatusBarController?

    override init() {
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        vm = BatteryViewModel(autoStart: isRunningUnitTests == false)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(vm: vm)
    }
}
