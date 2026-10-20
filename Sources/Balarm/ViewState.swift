import SwiftUI

// The macOS 27 SDK also exports a State macro. Name the property wrapper explicitly
// so Command Line Tools builds do not require the SwiftUIMacros plugin.
typealias ViewState<Value> = State<Value>
