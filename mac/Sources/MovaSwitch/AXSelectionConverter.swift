import ApplicationServices

final class AXSelectionConverter: SelectionConverting {
	private let translator: KeyboardLayoutTranslator
	private weak var inputSource: InputSourceControl?

	init(translator: KeyboardLayoutTranslator, inputSource: InputSourceControl) {
		self.translator = translator
		self.inputSource = inputSource
	}

	func convertSelection() -> RewriteAction? {
		guard let inputSource,
			  let originalLayout = inputSource.currentLayout(),
			  let element = focusedElement(),
			  !isSecure(element),
			  let selected = stringAttribute(kAXSelectedTextAttribute, from: element),
			  !selected.isEmpty,
			  let conversion = translator.selectionConversion(for: selected) else { return nil }

		var settable = DarwinBoolean(false)
		guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
			  settable.boolValue else {
			return nil
		}
		guard inputSource.select(conversion.target), inputSource.currentLayout() == conversion.target else {
			_ = inputSource.select(originalLayout)
			return nil
		}

		guard AXUIElementSetAttributeValue(
			element,
			kAXSelectedTextAttribute as CFString,
			conversion.replacement as CFString
		) == .success else {
			_ = inputSource.select(originalLayout)
			return nil
		}

		return RewriteAction(
			span: .selection,
			deleteCount: selected.count,
			insertText: conversion.replacement,
			switchTo: conversion.target
		)
	}

	private func focusedElement() -> AXUIElement? {
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(
			AXUIElementCreateSystemWide(),
			kAXFocusedUIElementAttribute as CFString,
			&value
		) == .success, let value else { return nil }
		return value as! AXUIElement
	}

	private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
		return value as? String
	}

	private func isSecure(_ element: AXUIElement) -> Bool {
		stringAttribute(kAXSubroleAttribute, from: element) == kAXSecureTextFieldSubrole
	}
}
