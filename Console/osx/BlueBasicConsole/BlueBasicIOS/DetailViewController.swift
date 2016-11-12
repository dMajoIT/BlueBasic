//
//  DetailViewController.swift
//  BlueBasicIOS
//
//  Created by tim on 10/3/14.
//  Copyright (c) 2014 tim. All rights reserved.
//

import UIKit
import CoreBluetooth

var _current: Device?
var _currentOwner: UIViewController?

class DetailViewController: UIViewController, UITextViewDelegate, DeviceDelegate, ConsoleProtocol {

  @IBOutlet weak var console: UITextView!

  var inputCharacteristic: CBCharacteristic?
  var outputCharacteristic: CBCharacteristic?
  var pending = ""
  
  var keyboardOpen: CGRect? = nil
  
  var delegate: ConsoleDelegate?
  
  var autoUpgrade: AutoUpdateFirmware?
  var recoveryMode = false
  var wrote = 0
  var written = 0
  
  var detailItem: AnyObject? {
    didSet {
      connectTo(detailItem as! Device) {
        success in
        if success {
          self.autoUpgrade = AutoUpdateFirmware(console: self)
          self.autoUpgrade!.detectUpgrade() {
            needupgrade in
            if needupgrade {
              self.status = "Upgrade available"
              self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Upgrade", style: .plain, target: self, action: #selector(DetailViewController.upgrade))
            } else {
              self.autoUpgrade = nil
              self.navigationItem.rightBarButtonItem = nil
            }
          }

        }
      }
    }
  }
  
  var current: Device? {
    get {
      return _current
    }
    set {
      _currentOwner = self
      _current = newValue
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    console.dataDetectorTypes = UIDataDetectorTypes()
    console.delegate = self
    console.layoutManager.allowsNonContiguousLayout = false // Fix scroll jump when keyboard dismissed
    self.navigationItem.title = status
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    NotificationCenter.default.addObserver(self, selector: #selector(DetailViewController.keyboardDidShow(_:)), name: NSNotification.Name(rawValue: "UIKeyboardDidShowNotification"), object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(DetailViewController.keyboardDidHide(_:)), name: NSNotification.Name(rawValue: "UIKeyboardDidHideNotification"), object: nil)
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if detailItem == nil {
      popover?.present(from: (view.window!.rootViewController as! UISplitViewController).displayModeButtonItem, permittedArrowDirections: .any, animated: true)
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "UIKeyboardDidShowNotification"), object: nil)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "UIKeyboardDidHideNotification"), object: nil)
    resignActive()
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
  }

  // MARK: - Console mechanics
  
  var status: String = "Not connected" {
    didSet {
      self.navigationItem.title = status
      if isConnected && !isRecoveryMode {
        console?.isEditable = true
        console.becomeFirstResponder()
      } else {
        console?.isEditable = false
      }
    }
  }
  
  var isConnected: Bool {
    get {
      return status == "Connected" || status == "Upgrade available"
    }
  }
  
  var isRecoveryMode: Bool {
    get {
      return recoveryMode
    }
  }
  
  // Workaround
  @nonobjc
  func setStatus(_ status: String) {
    self.status = status
  }
  
  // Workaround
  func setDelegate(_ delegate: ConsoleDelegate) {
    self.delegate = delegate
  }
  
  func connectTo(_ device: Device, onConnected: CompletionHandler? = nil) {
    disconnect() {
      success in
      self.status = "Connecting..."
      self.current = device
      device.connect() {
        success in
        if success {
          device.services() {
            list in
            if list[UUIDS.commsServiceUUID] != nil {
              self.inputCharacteristic = list[UUIDS.commsServiceUUID]!.characteristics[UUIDS.inputCharacteristicUUID]
              self.outputCharacteristic = list[UUIDS.commsServiceUUID]!.characteristics[UUIDS.outputCharacteristicUUID]
              if self.current == nil {
                self.status = "Failed"
                onConnected?(false)
              } else {
                self.current!.read(self.inputCharacteristic!) {
                  data in
                  if data == nil {
                    if list[UUIDS.oadServiceUUID] != nil {
                      self.current!.delegate = self
                      self.recoveryMode = true
                      self.status = "Recovery mode"
                      onConnected?(true)
                    } else {
                      self.status = "Failed"
                      self.disconnect()
                      onConnected?(false)
                    }
                  } else {
                    self.status = "Connected"
                    self.current!.delegate = self
                    self.current!.notify(UUIDS.inputCharacteristicUUID, serviceUUID: UUIDS.commsServiceUUID)
                    onConnected?(true)
                  }
                }
              }
            } else if list[UUIDS.oadServiceUUID] != nil {
              self.current!.delegate = self
              self.recoveryMode = true
              self.status = "Recovery mode"
              onConnected?(true)
            } else {
              self.status = "Unsupported"
              self.disconnect()
              onConnected?(false)
            }
          }
        } else {
          self.status = "Failed"
          onConnected?(false)
        }
      }
    }
  }
  
  func onWriteComplete(_ success: Bool, uuid: CBUUID) {
    written += 1
    if wrote > written {
      status = String(format: "Sending...%d%%", 100 * written / wrote)
    } else {
      status = "Connected"
      wrote = 0
      written = 0
    }
    delegate?.onWriteComplete(uuid)
  }
  
  func onNotification(_ success: Bool, uuid: CBUUID, data: Data) {
    switch uuid {
    case UUIDS.inputCharacteristicUUID:
      if delegate == nil || delegate!.onNotification(uuid, data: data) {
        let str = NSString(data: data, encoding: String.Encoding.ascii.rawValue)!
        console.selectedRange = NSMakeRange(console.text!.utf16.count, 0)
        console.insertText(str as String)
        console.scrollRangeToVisible(NSMakeRange(console.text!.utf16.count, 0))
      }
    default:
      break
    }
  }
  
  func onDisconnect() {
    if let old = current {
      old.connect()
    }
  }
  
  func disconnect(_ onDisconnect: CompletionHandler? = nil) {
    if let old = current {
      current = nil
      delegate = nil
      status = "Not connected"
      recoveryMode = false
      old.delegate = nil
      old.disconnect() {
        success in
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(1_000_000_000) / Double(NSEC_PER_SEC)) {
          if onDisconnect != nil {
            onDisconnect!(success)
          }
        }
      }
    } else {
      onDisconnect?(true)
    }
  }
  
  func write(_ str: String = "\n") {
    for ch in str.characters {
      pending.append(ch)
      if ch == "\n" || pending.utf16.count > 19 {
        current!.write(pending.data(using: String.Encoding.ascii, allowLossyConversion: false)!, characteristic: outputCharacteristic!, type: .withResponse)
        pending = ""
        wrote += 1
      }
    }
  }
  
  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    if current == nil {
      return false
    } else if text.utf16.count > 0 {
      write(text)
      if range.location == console.text.utf16.count {
        return true
      } else {
        console.selectedRange = NSMakeRange(console.text!.utf16.count, 0)
        console.insertText(text)
        console.scrollRangeToVisible(NSMakeRange(console.text.utf16.count, 0))
        return false
      }
    } else if range.location == console.text.utf16.count - 1 && pending.utf16.count > 0 {
      pending.remove(at: pending.characters.index(before: pending.endIndex))
      return true
    } else {
      return false
    }
  }
  
  func resignActive() {
    if _currentOwner == self {
      disconnect()
    }
  }

  func upgrade() {
    if autoUpgrade != nil {
      let alert = UIAlertController(title: "Upgrade?", message: "Do you want to upgrade the device firmware?", preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .destructive, handler: {
        action in
        self.navigationItem.rightBarButtonItem = nil
        UIApplication.shared.isIdleTimerDisabled = true
        self.autoUpgrade!.upgrade() {
          success in
          UIApplication.shared.isIdleTimerDisabled = false
        }
      }))
      alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: {
        action in
      }))
      self.present(alert, animated: true, completion: nil)
    }
  }

  
  func keyboardDidShow(_ notification: Notification) {
    if keyboardOpen == nil {
      let info = notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as! NSValue
      let size = info.cgRectValue.size

      var frame = console.frame
      keyboardOpen = frame
      let bottom = UIScreen.main.bounds.size.height - (frame.origin.y + frame.size.height)
      frame.size.height -= (size.height - bottom) + (console.font?.lineHeight)!
      console.frame = frame

      console.selectedRange = NSMakeRange(console.text!.utf16.count, 0)
      console.scrollRangeToVisible(NSMakeRange(console.text.utf16.count, 0))
    }
  }
  
  func keyboardDidHide(_ notification: Notification) {
    if keyboardOpen != nil {
      self.console.frame.size.height = self.keyboardOpen!.size.height
      self.keyboardOpen = nil
      self.console.scrollRangeToVisible(NSMakeRange(self.console.text.utf16.count, 0))
    }
  }

}
