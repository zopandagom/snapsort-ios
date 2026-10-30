import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.client(.backgroundIndexing, shared: [.core], clients: [.indexing, .tripPlace, .widgetTimeline])
