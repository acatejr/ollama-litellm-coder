terraform {
  required_version = ">= 1.3.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

# Look up the existing SSH keys already saved in your DigitalOcean account
data "digitalocean_ssh_key" "keys" {
  for_each = toset(var.ssh_key_names)
  name     = each.value
}

# DigitalOcean Droplet
resource "digitalocean_droplet" "ai_node" {
  image    = "ubuntu-24-04-x64"
  name     = "qwen-coder-ollama-litellm"
  region   = var.region
  size     = var.droplet_size
  ssh_keys = [for k in data.digitalocean_ssh_key.keys : k.fingerprint]

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    compose_b64        = base64encode(file("${path.module}/docker-compose.yml"))
    litellm_config_b64 = base64encode(file("${path.module}/litellm-config.yaml"))
    # Single quotes make docker compose read the value literally (no $ expansion).
    stack_env_b64 = base64encode(<<-EOT
      LITELLM_MASTER_KEY='${var.litellm_master_key}'
      LITELLM_API_KEY='${var.litellm_api_key}'
    EOT
    )
  })

  lifecycle {
    precondition {
      condition     = var.litellm_api_key != var.litellm_master_key
      error_message = "litellm_api_key must be different from litellm_master_key."
    }
  }
}

# Firewall Configuration
resource "digitalocean_firewall" "ai_node_fw" {
  name = "ollama-litellm-firewall"

  droplet_ids = [digitalocean_droplet.ai_node.id]

  # Allow inbound SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow inbound LiteLLM traffic
  inbound_rule {
    protocol         = "tcp"
    port_range       = "4000"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound traffic
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}