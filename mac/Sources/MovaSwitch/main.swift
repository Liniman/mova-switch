import AppKit
import Darwin

if let status = TestCommand.runIfRequested(CommandLine.arguments) {
	exit(status)
} else {
	let application = NSApplication.shared
	let delegate = AppDelegate()
	application.delegate = delegate
	application.run()
}
