import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.feature(.sampleRecorder, clients: [.photoLibrary, .imageAnalysis], shared: [.core])
