import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(.library, clients: [.photoLibrary, .indexing], shared: [.core])
