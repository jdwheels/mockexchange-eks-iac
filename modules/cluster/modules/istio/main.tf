provider "kubernetes" {
  config_context = "trivialepic"
}

locals {
  repository = "https://istio-release.storage.googleapis.com/charts"
}

resource "kubernetes_namespace" "istio" {
  metadata {
    name = "istio-system"
  }
}

resource "helm_release" "istio_base" {
  repository = local.repository
  chart      = "base"
  name       = "istio-base"
  namespace  = kubernetes_namespace.istio.metadata[0].name
}

locals {
  istio_version = "1.13.4"
}

resource "helm_release" "istiod" {
  repository = local.repository
  version    = local.istio_version
  chart      = "istiod"
  name       = "istiod"
  namespace  = kubernetes_namespace.istio.metadata[0].name
  depends_on = [
    helm_release.istio_base
  ]
}

terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "4.26.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
  }
}

provider "github" {
  owner = "istio"
}

data "github_repository" "istio" {
  full_name = "istio/istio"

}

locals {
  addons = toset(["kiali", "prometheus", "jaeger", "grafana"])
}

data "github_repository_file" "addons" {
  for_each   = local.addons
  file       = "samples/addons/${each.value}.yaml"
  branch     = "release-1.13"
  repository = data.github_repository.istio.name
}

provider "kubectl" {
  config_context = "trivialepic"
}

data "kubectl_file_documents" "addons" {
  for_each = local.addons
  content  = data.github_repository_file.addons[each.value].content
}

locals {
  manifests = flatten([
    for addon in local.addons : [
      for id, content in data.kubectl_file_documents.addons[addon].manifests : {
        id      = id
        content = content
      }
    ]
  ])
}

resource "kubectl_manifest" "addons" {
  for_each = {
    for manifest in local.manifests : manifest["id"] => manifest["content"]
  }
  yaml_body = each.value
}
