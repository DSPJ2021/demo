terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.5.0"
    }
  }
}

provider "google" {
  credentials = file("credentials.json")

  project = var.project
  region  = "us-central1"
  zone    = "us-central1-c"
}

resource "google_compute_project_metadata" "my_ssh_key" {
  metadata = {
    ssh-keys = join("\n", [for key in var.ssh_keys : "${key.user}:${key.keymaterial}"])
  }
}

resource "google_compute_subnetwork" "subnet_with_logging" {
  name          = "syncmesh-subnetwork"
  ip_cidr_range = "10.2.0.0/16"
  region        = "us-central1"
  network       = google_compute_network.vpc_network.id



  log_config {

    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 1
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_network" "vpc_network" {
  name                    = "syncmesh-network"
  auto_create_subnetworks = false

}



data "google_compute_image" "container_optimized_image" {
  # Use a container optimized image
  # See a list of all images : https://console.cloud.google.com/compute/images
  family  = "ubuntu-2004-lts"
  project = "ubuntu-os-cloud"
}


resource "google_compute_instance" "vm_instance" {
  count        = var.instance_count
  name         = "syncmesh-instance-${count.index}"
  machine_type = "f1-micro"

  tags = ["demo-vm-instance"]
  metadata = {
    ssh-keys = join("\n", [for key in var.ssh_keys : "${key.user}:${key.keymaterial}"])
  }


  boot_disk {
    initialize_params {
      image = data.google_compute_image.container_optimized_image.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_with_logging.name
    access_config {
    }
  }
  metadata_startup_script = file("${path.module}/setup_scripts/syncmesh-startup.sh")
}

resource "google_compute_instance" "client" {
  name         = "client-instance"
  machine_type = "f1-micro"

  tags = ["demo-vm-instance"]
  metadata = {
    ssh-keys = join("\n", [for key in var.ssh_keys : "${key.user}:${key.keymaterial}"])
  }


  boot_disk {
    initialize_params {
      image = data.google_compute_image.container_optimized_image.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_with_logging.name
    access_config {
    }
  }
  metadata_startup_script = templatefile("${path.module}/setup_scripts/client-startup.tpl", { instances = google_compute_instance.vm_instance })
}

resource "google_compute_instance" "central-server" {
  name         = "central-server-instance"
  machine_type = "f1-micro"

  tags = ["demo-vm-instance"]
  metadata = {
    ssh-keys = join("\n", [for key in var.ssh_keys : "${key.user}:${key.keymaterial}"])
  }


  boot_disk {
    initialize_params {
      image = data.google_compute_image.container_optimized_image.self_link
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet_with_logging.name
    access_config {
    }
  }
  metadata_startup_script = templatefile("${path.module}/setup_scripts/central-server-startup.tpl", { instances = google_compute_instance.vm_instance })
#   metadata_startup_script = file("${path.module}/setup_scripts/central-server-startup.tpl")
}


resource "google_compute_firewall" "ssh-rule" {
  name    = "demo-ssh"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  target_tags   = ["demo-vm-instance"]
  source_ranges = ["0.0.0.0/0"]
}

## Log Export
resource "google_logging_project_sink" "sink" {
  name        = "syncmesh-sink"
  project     = var.project
  filter      = "resource.type=\"gce_subnetwork\""
  destination = "bigquery.googleapis.com/${google_bigquery_dataset.dataset.id}"
  #   unique_writer_identity = var.unique_writer_identity
#   unique_writer_identity = true
}

resource "google_bigquery_dataset" "dataset" {
  dataset_id                  = "syncmesh"
  friendly_name               = "syncmesh"
  description                 = "Syncmesh export dataset"
  location                    = "EU"
  default_table_expiration_ms = 36000000

  labels = {
    env = "default"
  }

  access {
    role          = "OWNER"
    user_by_email = "habenicht456@gmail.com"
  }
}

resource "google_storage_bucket" "bucket" {
  name          = "syncmesh-log-bucket"
  force_destroy = false
}
