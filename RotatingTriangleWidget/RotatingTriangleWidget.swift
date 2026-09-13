import SwiftUI
import WidgetKit

struct RotatingTriangleEntry: TimelineEntry {
    let date: Date
}

struct RotatingTriangleProvider: TimelineProvider {
    func placeholder(in context: Context) -> RotatingTriangleEntry {
        RotatingTriangleEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (RotatingTriangleEntry) -> Void) {
        completion(RotatingTriangleEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RotatingTriangleEntry>) -> Void) {
        completion(Timeline(entries: [RotatingTriangleEntry(date: Date())], policy: .never))
    }
}

struct RotatingTriangleWidgetView: View {
    var entry: RotatingTriangleEntry

    var body: some View {
        RotatingRedTriangle()
            .padding(18)
            .containerBackground(.black, for: .widget)
    }
}

struct RotatingTriangleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RotatingTriangleWidget", provider: RotatingTriangleProvider()) { entry in
            RotatingTriangleWidgetView(entry: entry)
        }
        .configurationDisplayName("Rotating Triangle")
        .description("A red triangle that rotates.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct RotatingTriangleWidgetBundle: WidgetBundle {
    var body: some Widget {
        RotatingTriangleWidget()
    }
}

#Preview(as: .systemSmall) {
    RotatingTriangleWidget()
} timeline: {
    RotatingTriangleEntry(date: .now)
}
