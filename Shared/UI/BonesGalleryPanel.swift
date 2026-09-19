import SwiftUI

/// Right-side bone art rail — Android `BonesGalleryFragment`.
struct BonesGalleryPanel: View {
    var bones: [UnitAssets.GalleryBone]
    var highlightedBmName: String?
    var onNewBone: () -> Void
    var onAttach: (String) -> Void
    var onEdit: (String) -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                newBoneHeader
                    .frame(height: SkeletonChrome.galleryRowHeight)
                ForEach(bones) { bone in
                    boneRow(bone)
                        .frame(height: SkeletonChrome.galleryRowHeight)
                }
            }
        }
        .frame(width: SkeletonChrome.galleryWidth(horizontalSizeClass: horizontalSizeClass))
        .frame(maxHeight: .infinity)
        .background(Color.clear)
    }

    private var newBoneHeader: some View {
        Button(action: onNewBone) {
            ZStack {
                Rectangle()
                    .fill(SkeletonChrome.galleryNewBone)
                HStack(spacing: 6) {
                    Image(decorative: Self.plusIcon, scale: UIScreen.main.scale)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("NEW\nBONE")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("New Bone")
    }

    private func boneRow(_ bone: UnitAssets.GalleryBone) -> some View {
        Button {
            onAttach(bone.bmName)
        } label: {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(SkeletonChrome.galleryThumbFill)
                Image(decorative: bone.thumb, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if bone.bmName == highlightedBmName {
                    SkeletonChrome.galleryHighlight
                        .frame(width: 6)
                        .frame(maxHeight: .infinity)
                }
                VStack {
                    Rectangle()
                        .fill(Color(white: 0.67).opacity(0x55 / 255))
                        .frame(height: 1)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Attach Bone") { onAttach(bone.bmName) }
            Button("Edit Bone") { onEdit(bone.bmName) }
        }
        .accessibilityLabel("Bone \(bone.bmName)")
    }

    private static let plusIcon: CGImage = {
        guard let url = Bundle.main.url(forResource: "plus_icon", withExtension: "png", subdirectory: "chrome")
            ?? Bundle.main.url(forResource: "plus_icon", withExtension: "png")
        else {
            fatalError("chrome missing plus_icon.png")
        }
        do {
            let data = try Data(contentsOf: url)
            return PNGImage.cgImage(from: data, name: "chrome/plus_icon.png")
        } catch {
            fatalError("chrome could not read \(url.path): \(error)")
        }
    }()
}
