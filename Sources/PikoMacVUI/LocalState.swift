import SwiftUI

// Komut Satırı Araçları'nda SwiftUIMacros eklentisi olmadığından `@State` makrosu derlenmez;
// aynı işi gören basit bir yerel durum sarmalayıcısı.
final class LocalBox<T>: ObservableObject {
    @Published var value: T
    init(_ v: T) { value = v }
}

@propertyWrapper
struct Local<T>: DynamicProperty {
    @StateObject private var box: LocalBox<T>
    init(wrappedValue: T) { _box = StateObject(wrappedValue: LocalBox(wrappedValue)) }
    var wrappedValue: T {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: SwiftUI.Binding<T> {
        SwiftUI.Binding(get: { box.value }, set: { box.value = $0 })
    }
}
