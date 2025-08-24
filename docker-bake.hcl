# Variables to be specified externally.
variable "registry" {
  default = "ghcr.io/theory"
  description = "The image registry."
}

variable "version" {
  default = ""
  description = "The release version."
}

variable "revision" {
  default = ""
  description = "The current Git commit SHA."
}

# Values to use in the targets.
name = "demo"
now = timestamp()
authors = "David E. Wheeler"
url = "https://github.com/theory/demo"

target "default" {
  platforms = ["linux/amd64", "linux/arm64"]
  context = "."
  tags = [
    "${registry}/${name}:latest",
    "${registry}/${name}:${version}",
  ]
  annotations = [
    "index,manifest:org.opencontainers.image.created=${now}",
    "index,manifest:org.opencontainers.image.url=${url}",
    "index,manifest:org.opencontainers.image.source=${url}",
    "index,manifest:org.opencontainers.image.version=${version}",
    "index,manifest:org.opencontainers.image.revision=${revision}",
    "index,manifest:org.opencontainers.image.vendor=${authors}",
    "index,manifest:org.opencontainers.image.title=Theory Demo",
    "index,manifest:org.opencontainers.image.description=Run theory’s demo presentations.",
    "index,manifest:org.opencontainers.image.documentation=${url}",
    "index,manifest:org.opencontainers.image.authors=${authors}",
    "index,manifest:org.opencontainers.image.licenses=MIT",
    "index,manifest:org.opencontainers.image.base.name=perl",
  ]
  labels = {
    "org.opencontainers.image.created" = "${now}",
    "org.opencontainers.image.url" = "${url}",
    "org.opencontainers.image.source" = "${url}",
    "org.opencontainers.image.version" = "${version}",
    "org.opencontainers.image.revision" = "${revision}",
    "org.opencontainers.image.vendor" = "${authors}",
    "org.opencontainers.image.title" = "Theory Demo",
    "org.opencontainers.image.description" = "Run theory’s demo presentations.",
    "org.opencontainers.image.documentation" = "${url}",
    "org.opencontainers.image.authors" = "${authors}",
    "org.opencontainers.image.licenses" = "MIT"
    "org.opencontainers.image.base.name" = "perl",
  }
}
