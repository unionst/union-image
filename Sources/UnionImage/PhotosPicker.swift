//
//  PhotosPicker.swift
//  union-image
//
//  Created by Ben Sage on 4/27/25.
//

import SwiftUI

public struct PhotosPicker<Label: View>: View {
    @Binding var selection: UIImage?
    var crop: Bool
    var label: Label

    @State private var showSheet = false

    public init(
        _ title: String,
        selection: Binding<UIImage?>,
        crop: Bool
    ) where Label == Text {
        label = Text(title)
        _selection = selection
        self.crop = crop
    }

    public init(
        selection: Binding<UIImage?>,
        crop: Bool,
        @ViewBuilder label: () -> Label
    ) {
        _selection = selection
        self.crop = crop
        self.label = label()
    }

    public var body: some View {
        Button {
            showSheet = true
        } label: {
            label
        }
        .sheet(isPresented: $showSheet) {
            ImagePickerNavigation(image: $selection)
        }
    }
}

#Preview {
    @Previewable @State var image: UIImage?
    PhotosPicker("Tap me", selection: $image, crop: true)
}
