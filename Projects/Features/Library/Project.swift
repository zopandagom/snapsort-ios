import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(
  .library,
  clients: [.photoLibrary, .indexing, .photoStore, .notification, .imageAnalysis, .map, .pasteboard, .widgetTimeline],
  shared: [.core, .designSystem]
)
