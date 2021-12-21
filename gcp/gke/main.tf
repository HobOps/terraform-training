# Variables
variable "project" {
  description = "Project"
  default = "hobops-training-a"
}



#################
# Aqui activamos servicios
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_project_service
resource "google_project_service" "compute" {
  project = var.project
  service = "compute.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}

resource "google_project_service" "container" {
  project = var.project
  service = "container.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_dependent_services = true
}


######################
# Este modulo crea la VPC 
# https://github.com/terraform-google-modules/terraform-google-network
module "vpc" {
    source  = "terraform-google-modules/network/google"
    version = "~> 3.0"
    depends_on = [google_project_service.compute]

    project_id   = var.project
    network_name = "vpc-training"
    routing_mode = "GLOBAL"

    subnets = [
        {
            subnet_name           = "subnet-01"
            subnet_ip             = "10.10.0.0/16"
            subnet_region         = "us-central1"
        },
    ]

    secondary_ranges = {
        subnet-01 = [
            {
                range_name    = "subnet-01-pods"
                ip_cidr_range = "10.11.0.0/16"
            },
            {
                range_name    = "subnet-01-services"
                ip_cidr_range = "10.12.0.0/16"
            },
        ]
    }

    routes = [
        {
            name                   = "egress-internet"
            description            = "route through IGW to access internet"
            destination_range      = "0.0.0.0/0"
            tags                   = "egress-inet"
            next_hop_internet      = "true"
        },
    ]
}


output "test" {
  value = "hola mundo!"
}

output "vpc_name" {
  value = module.vpc.network_name
}

output "vpc_id" {
  value = module.vpc.network_id
}



#########################

# Este modulo crea el cluster de GKE
# https://github.com/terraform-google-modules/terraform-google-kubernetes-engine


# google_client_config and kubernetes provider must be explicitly specified like the following.
data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

module "gke" {
  source                     = "terraform-google-modules/kubernetes-engine/google"
  version = "17.3.0"
  depends_on = [google_project_service.container]
  project_id                 = var.project
  name                       = "gke-test-1"
  region                     = "us-central1"
  regional                   = false
  zones                      = ["us-central1-a"]
  network                    = module.vpc.network_name
  subnetwork                 = "subnet-01"
  ip_range_pods              = "subnet-01-pods"
  ip_range_services          = "subnet-01-services"
  http_load_balancing        = false
  horizontal_pod_autoscaling = true
  network_policy             = false
  create_service_account     = false

  node_pools = [
    {
      name                      = "default-node-pool"
      machine_type              = "e2-medium"
      node_locations            = "us-central1-b,us-central1-c"
      min_count                 = 1
      max_count                 = 5
      local_ssd_count           = 0
      disk_size_gb              = 100
      disk_type                 = "pd-standard"
      image_type                = "COS"
      auto_repair               = true
      auto_upgrade              = true
      preemptible               = false
      initial_node_count        = 2
    },
  ]

  node_pools_oauth_scopes = {
    all = []

    default-node-pool = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }

  node_pools_labels = {
    all = {}

    default-node-pool = {
      default-node-pool = true
    }
  }

  node_pools_metadata = {
    all = {}

    default-node-pool = {
      node-pool-metadata-custom-value = "my-node-pool"
    }
  }

  node_pools_taints = {
    all = []

    default-node-pool = [
      {
        key    = "default-node-pool"
        value  = true
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
  }

  node_pools_tags = {
    all = []

    default-node-pool = [
      "default-node-pool",
    ]
  }
}