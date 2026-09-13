import CoreGraphics

enum ItemConstructor {
    static func spider() -> StickmanUnit {
        var unit = StickmanUnit(
            name: "newstickman:spider",
            points: [
                StickmanPoint(id: 1, x: 0, y: 0, isBase: true, parentId: nil),
                StickmanPoint(id: 2, x: 213, y: -4, isBase: false, parentId: 1),
                StickmanPoint(id: 3, x: 131, y: -69, isBase: false, parentId: 1),
                StickmanPoint(id: 4, x: 188, y: -155, isBase: false, parentId: 3),
                StickmanPoint(id: 5, x: 278, y: -139, isBase: false, parentId: 4),
                StickmanPoint(id: 6, x: 132, y: 60, isBase: false, parentId: 1),
                StickmanPoint(id: 7, x: 216, y: 121, isBase: false, parentId: 6),
                StickmanPoint(id: 8, x: 292, y: 76, isBase: false, parentId: 7),
                StickmanPoint(id: 9, x: 71, y: -81, isBase: false, parentId: 1),
                StickmanPoint(id: 10, x: 88, y: -164, isBase: false, parentId: 9),
                StickmanPoint(id: 11, x: 146, y: -216, isBase: false, parentId: 10),
                StickmanPoint(id: 12, x: 81, y: 76, isBase: false, parentId: 1),
                StickmanPoint(id: 13, x: 105, y: 154, isBase: false, parentId: 12),
                StickmanPoint(id: 14, x: 168, y: 200, isBase: false, parentId: 13),
                StickmanPoint(id: 15, x: 20, y: -63, isBase: false, parentId: 1),
                StickmanPoint(id: 16, x: 29, y: 58, isBase: false, parentId: 1),
                StickmanPoint(id: 17, x: 45, y: 132, isBase: false, parentId: 16),
                StickmanPoint(id: 18, x: -25, y: 168, isBase: false, parentId: 17),
                StickmanPoint(id: 19, x: 36, y: -143, isBase: false, parentId: 15),
                StickmanPoint(id: 20, x: -41, y: -145, isBase: false, parentId: 19),
                StickmanPoint(id: 21, x: -9, y: -47, isBase: false, parentId: 1),
                StickmanPoint(id: 22, x: -5, y: 44, isBase: false, parentId: 1),
                StickmanPoint(id: 23, x: -67, y: -81, isBase: false, parentId: 21),
                StickmanPoint(id: 24, x: -61, y: 77, isBase: false, parentId: 22),
                StickmanPoint(id: 25, x: -114, y: 41, isBase: false, parentId: 24),
                StickmanPoint(id: 26, x: -129, y: -47, isBase: false, parentId: 23),
            ],
            edges: []
        )
        unit.link()
        return unit
    }

    static let sceneWidth: CGFloat = 640
    static let sceneHeight: CGFloat = 480

    static func scene(unit: StickmanUnit, scale: CGFloat = 1, frameCount: Int = 1) -> StickmanScene {
        if frameCount < 1 {
            fatalError("ItemConstructor scene frameCount must be >= 1, got \(frameCount)")
        }
        let frames = (0..<frameCount).map { index in
            var copy = unit
            copy.placeInScene(width: sceneWidth, height: sceneHeight, scale: scale)
            return StickmanFrame(id: index, units: [copy])
        }
        return StickmanScene(
            width: sceneWidth,
            height: sceneHeight,
            frames: frames,
            currentIndex: 0
        )
    }
}
