//
//  ColorPreviewWithHex.swift
//  FlexColorPicker
//
//  Created by Rastislav Mirek on 1/6/18.
//  
//	MIT License
//  Copyright (c) 2018 Rastislav Mirek
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:

//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.

//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import UIKit

internal let colorPreviewWithHexIntristicContentSize = CGSize(width: 110, height: 96)
internal let defaultHexLabelHeight: CGFloat = 32
private let hexFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
private let defaultCornerradius: CGFloat = 5
private let invalidBorderColor = UIColor(red: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)

private let confirmAnimationScaleRatio: CGFloat = 0.87
private let confirmAnimationSpringDamping: CGFloat = 0.7
private let confirmAnimationDuration = 0.3

/// A color control that displays currently selected color. It allows the user to evaluate if it is the color they want.
///
/// When tapped, it animates and sends `primaryActionTriggered` event. This event is interpreted as user confirming current color as final picked color by the `ColorPickerController`.
@IBDesignable
open class ColorPreviewWithHex: AbstractColorControl, UITextFieldDelegate {
    private var labelHeightConstraint = NSLayoutConstraint()
    private var updatingFromWheel = false

    /// A subview that shows example of selected color. It is set as its `backgroundColor`.
    public let colorView = UIView()
    /// White "Copy" label centered over `colorView`.
    public let copyTitleLabel = UILabel()
    /// A label subview that shows hex value of selected color as text (kept for API compatibility).
    public let hexLabel = UILabel()
    /// Editable 6-digit `#RRGGBB` hex text field.
    public let hexTextField = UITextField()
    /// Called whenever the hex text field validity changes (`true` when valid 6-digit `#RRGGBB`).
    public var onHexValidityChanged: ((Bool) -> Void)?
    /// Whether the current hex text field value parses as a valid 6-digit `#RRGGBB` color.
    public private(set) var isHexValid: Bool = true

    /// Convinience layout anchor that corresponds to bottom edge of `colorView`. This might not be equivalent of `bottomAnchor` as the `hexLabel` is below `colorView` (it it is displayed).
    ///
    /// Use this to align other views to `colorView`.
    open var hexLabelToLayoutAnchor: NSLayoutYAxisAnchor {
        return hexTextField.topAnchor
    }

    /// Whether to show (`true`) or hide (`false`) the subview that shows hex value of currently selected color (the `hexLabel`).
    @IBInspectable
    public var displayHex: Bool = true {
        didSet {
            updateLabelHeight()
        }
    }

    /// The desired height of the area displaying hex value of currently selected color.
    @IBInspectable
    public var hexHeight: CGFloat = defaultHexLabelHeight {
        didSet {
            updateLabelHeight()
        }
    }

    /// Text color of the hex label that displys hex value of currently selected color.
    @IBInspectable
    public var textColor: UIColor = UIColor.colorPickerLabelTextColor {
        didSet {
            hexLabel.textColor = textColor
            hexTextField.textColor = textColor
        }
    }

    /// Whether to display default thin border around the preview.
    @IBInspectable
    public var borderOn: Bool = true {
        didSet {
            updateBorder(visible: borderOn, view: self)
        }
    }

    /// Corner radius of the preview.
    ///
    /// You can set it to very high value to make the view oval (or circular if bounds are square).
    @IBInspectable
    public var cornerRadius: CGFloat = defaultCornerradius {
        didSet {
            updateCornerRadius()
        }
    }

    ///If `true`, the preview will respond to touches, animating and sending `primaryActionTriggered` event on `touchUpInside`.
    @IBInspectable
    public var tapToConfirm: Bool = true

    open override var bounds: CGRect {
        didSet {
            updateCornerRadius()
        }
    }

    open override var intrinsicContentSize: CGSize {
        return colorPreviewWithHexIntristicContentSize
    }

    open override func commonInit() {
        super.commonInit()

        addSubview(colorView)
        colorView.translatesAutoresizingMaskIntoConstraints = false

        colorView.addSubview(copyTitleLabel)
        copyTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        copyTitleLabel.text = "Copy"
        copyTitleLabel.textColor = .white
        copyTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        copyTitleLabel.textAlignment = .center
        copyTitleLabel.layer.shadowColor = UIColor.black.cgColor
        copyTitleLabel.layer.shadowOpacity = 0.55
        copyTitleLabel.layer.shadowRadius = 2
        copyTitleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        copyTitleLabel.centerXAnchor.constraint(equalTo: colorView.centerXAnchor).isActive = true
        copyTitleLabel.centerYAnchor.constraint(equalTo: colorView.centerYAnchor).isActive = true

        addSubview(hexTextField)
        hexTextField.translatesAutoresizingMaskIntoConstraints = false

        colorView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        colorView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        colorView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        colorView.bottomAnchor.constraint(equalTo: hexTextField.topAnchor).isActive = true

        hexTextField.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        hexTextField.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        labelHeightConstraint = hexTextField.heightAnchor.constraint(equalToConstant: hexHeight)
        labelHeightConstraint.priority = .init(999)
        labelHeightConstraint.isActive = true
        hexTextField.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        updateLabelHeight()

        hexLabel.textColor = textColor
        hexLabel.textAlignment = .center
        hexLabel.font = hexFont

        hexTextField.textColor = textColor
        hexTextField.textAlignment = .center
        hexTextField.font = hexFont
        hexTextField.placeholder = "#RRGGBB"
        hexTextField.keyboardType = .asciiCapable
        hexTextField.autocapitalizationType = .allCharacters
        hexTextField.autocorrectionType = .no
        hexTextField.spellCheckingType = .no
        hexTextField.returnKeyType = .done
        hexTextField.delegate = self
        hexTextField.addTarget(self, action: #selector(handleHexEditingChanged), for: .editingChanged)

        updateBorder(visible: borderOn, view: self)
        setSelectedHSBColor(selectedHSBColor, isInteractive: false) // set default color if it is not set, otherwise keep color set in storyboard via IBInspectable
        updateCornerRadius()
    }

    open override func setSelectedHSBColor(_ hsbColor: HSBColor, isInteractive interactive: Bool) {
        super.setSelectedHSBColor(hsbColor, isInteractive: interactive)
        let color = hsbColor.toUIColor()
        colorView.backgroundColor = color
        let formatted = "#\(color.hexValue())"
        hexLabel.text = formatted
        if !updatingFromWheel {
            updatingFromWheel = true
            hexTextField.text = formatted
            updatingFromWheel = false
            setValidity(true)
        }
    }

    public static func parseSixDigitHex(_ raw: String) -> UIColor? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6 else { return nil }
        for scalar in hex.unicodeScalars {
            let v = scalar.value
            let isDigit = v >= 48 && v <= 57
            let isUpper = v >= 65 && v <= 70
            let isLower = v >= 97 && v <= 102
            if !isDigit && !isUpper && !isLower {
                return nil
            }
        }
        guard let rgb = Int(hex, radix: 16) else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    public func parsedHexColor() -> UIColor? {
        Self.parseSixDigitHex(hexTextField.text ?? "")
    }

    @objc private func handleHexEditingChanged() {
        if updatingFromWheel { return }
        guard let parsed = Self.parseSixDigitHex(hexTextField.text ?? "") else {
            setValidity(false)
            return
        }
        setValidity(true)
        updatingFromWheel = true
        let nextHSB = parsed.hsbColor
        super.setSelectedHSBColor(nextHSB, isInteractive: true)
        colorView.backgroundColor = parsed
        hexLabel.text = "#\(parsed.hexValue())"
        sendActions(for: .valueChanged)
        updatingFromWheel = false
    }

    private func setValidity(_ valid: Bool) {
        isHexValid = valid
        if valid {
            hexTextField.layer.borderWidth = 0
            hexTextField.layer.borderColor = nil
            updateBorder(visible: borderOn, view: self)
        } else {
            layer.borderWidth = 1.5
            layer.borderColor = invalidBorderColor.cgColor
        }
        onHexValidityChanged?(valid)
    }

    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let current = textField.text ?? ""
        guard let strRange = Range(range, in: current) else { return false }
        let next = current.replacingCharacters(in: strRange, with: string.uppercased())
        let maxLen = next.hasPrefix("#") ? 7 : 6
        if next.count > maxLen {
            return false
        }
        for (idx, scalar) in next.unicodeScalars.enumerated() {
            if idx == 0, scalar == "#" { continue }
            let v = scalar.value
            let isHex = (v >= 48 && v <= 57) || (v >= 65 && v <= 70) || (v >= 97 && v <= 102)
            if !isHex {
                return false
            }
        }
        return true
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func updateLabelHeight() {
        labelHeightConstraint.constant = displayHex ? hexHeight : 0
        hexTextField.isHidden = !displayHex
    }
    
    /// Updates  border color of the color preview when interface is changed to dark or light mode.
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 13.0, *), traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle  {
            if isHexValid {
                updateBorder(visible: borderOn, view: self)
            }
        }
    }

    private func handleTouchDown() {
        if !tapToConfirm {
            return
        }
        UIView.animate(withDuration: confirmAnimationDuration, delay: 0, usingSpringWithDamping: confirmAnimationSpringDamping, initialSpringVelocity: 0, options: [], animations: {
            self.layer.transform = CATransform3DMakeScale(confirmAnimationScaleRatio, confirmAnimationScaleRatio, 1)
        }, completion: nil)
    }

    private func handleTouchUp(valid: Bool) {
        if !tapToConfirm {
            return
        }
        UIView.animate(withDuration: confirmAnimationDuration, delay: 0, usingSpringWithDamping: confirmAnimationSpringDamping, initialSpringVelocity: 0, options: [], animations:  {
            self.layer.transform = CATransform3DIdentity
        }) { _ in
            if valid {
                self.sendActions(for: .primaryActionTriggered)
            }
        }
    }

    private func updateCornerRadius() {
        cornerRadius_ = min(cornerRadius, bounds.height / 2, bounds.width / 2)
        if cornerRadius_ > 0 {
            clipsToBounds = true
        }
    }
}

extension ColorPreviewWithHex {
    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = locationForTouches(touches), point(inside: location, with: event) else {
            return
        }
        if hexTextField.frame.contains(location) {
            return
        }
        handleTouchDown()
        super.touchesBegan(touches, with: event)
    }

    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = locationForTouches(touches) else {
            return
        }
        if hexTextField.frame.contains(location) {
            return
        }
        handleTouchUp(valid: point(inside: location, with: event) && isHexValid)
        super.touchesEnded(touches, with: event)
    }

    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        handleTouchUp(valid: false)
        super.touchesCancelled(touches, with: event)
    }

    open override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
