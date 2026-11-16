import AppKit

final class E2EHostDelegate: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate {
	private var window: NSWindow!
	private var normalText: NSTextView!
	private var secureText: NSSecureTextField!
	private var normalStatus: NSTextField!
	private var secureStatus: NSTextField!

	func applicationDidFinishLaunching(_ notification: Notification) {
		let content = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 360))
		window = NSWindow(
			contentRect: content.bounds,
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: false
		)
		window.title = "MovaSwitch E2E"
		window.contentView = content

		let normalLabel = NSTextField(labelWithString: "Normal text")
		normalLabel.frame = NSRect(x: 30, y: 310, width: 200, height: 24)
		content.addSubview(normalLabel)

		let scroll = NSScrollView(frame: NSRect(x: 30, y: 190, width: 560, height: 115))
		scroll.hasVerticalScroller = true
		normalText = NSTextView(frame: scroll.bounds)
		normalText.delegate = self
		normalText.setAccessibilityLabel("Normal test field")
		scroll.documentView = normalText
		content.addSubview(scroll)

		let clearNormal = NSButton(title: "Clear normal", target: self, action: #selector(clearNormalText))
		clearNormal.frame = NSRect(x: 470, y: 155, width: 120, height: 28)
		clearNormal.setAccessibilityLabel("Clear normal")
		content.addSubview(clearNormal)

		normalStatus = NSTextField(labelWithString: "normal-value=")
		normalStatus.frame = NSRect(x: 30, y: 155, width: 420, height: 24)
		normalStatus.setAccessibilityLabel("normal-value=")
		content.addSubview(normalStatus)

		let secureLabel = NSTextField(labelWithString: "Secure text")
		secureLabel.frame = NSRect(x: 30, y: 115, width: 200, height: 24)
		content.addSubview(secureLabel)

		secureText = NSSecureTextField(frame: NSRect(x: 30, y: 78, width: 420, height: 28))
		secureText.delegate = self
		secureText.setAccessibilityLabel("Secure test field")
		content.addSubview(secureText)

		let clearSecure = NSButton(title: "Clear secure", target: self, action: #selector(clearSecureText))
		clearSecure.frame = NSRect(x: 470, y: 78, width: 120, height: 28)
		clearSecure.setAccessibilityLabel("Clear secure")
		content.addSubview(clearSecure)

		secureStatus = NSTextField(labelWithString: "secure-result=empty")
		secureStatus.frame = NSRect(x: 30, y: 40, width: 560, height: 24)
		secureStatus.setAccessibilityLabel("secure-result=empty")
		content.addSubview(secureStatus)

		window.center()
		window.orderFront(nil)
	}

	func textDidChange(_ notification: Notification) {
		let value = normalText.string.replacingOccurrences(of: "\n", with: "\\n")
		normalStatus.stringValue = "normal-value=\(value)"
		normalStatus.setAccessibilityLabel(normalStatus.stringValue)
	}

	func controlTextDidChange(_ notification: Notification) {
		let value = secureText.stringValue
		secureStatus.stringValue = value == "ghbdsn " ? "secure-result=untouched" : "secure-result=length-\(value.count)"
		secureStatus.setAccessibilityLabel(secureStatus.stringValue)
	}

	@objc private func clearNormalText() {
		normalText.string = ""
		textDidChange(Notification(name: NSText.didChangeNotification))
		window.makeFirstResponder(normalText)
	}

	@objc private func clearSecureText() {
		secureText.stringValue = ""
		secureStatus.stringValue = "secure-result=empty"
		secureStatus.setAccessibilityLabel(secureStatus.stringValue)
		window.makeFirstResponder(secureText)
	}
}

let app = NSApplication.shared
let delegate = E2EHostDelegate()
app.delegate = delegate
app.run()
