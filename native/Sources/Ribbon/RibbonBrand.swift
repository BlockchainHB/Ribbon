import AppKit

@MainActor
enum RibbonBrand {
  static var applicationIcon: NSImage {
    if let url = Bundle.main.url(forResource: "Ribbon", withExtension: "icns"),
      let image = NSImage(contentsOf: url)
    {
      return image
    }
    return NSApp.applicationIconImage
  }

  static var menuIcon: NSImage? {
    guard let url = Bundle.main.url(forResource: "RibbonMenuTemplate", withExtension: "pdf"),
      let image = NSImage(contentsOf: url)
    else { return nil }
    image.size = NSSize(width: 18, height: 18)
    image.isTemplate = true
    return image
  }

  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"
  }
}
