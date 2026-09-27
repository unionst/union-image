import SwiftUI
import UIKit

struct DissolvingImage: View {
    let image: UIImage
    let size: CGSize
    let cornerRadius: Double
    let dissolve: ImageDissolve

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .blur(radius: dissolve.blurRadius)
            .opacity(dissolve.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
