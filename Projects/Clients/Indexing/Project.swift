import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.client(
  .indexing,
  shared: [.core],
  clients: [.photoLibrary, .imageAnalysis, .photoStore, .classifier]
)
