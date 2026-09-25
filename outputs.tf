output "droplet_ip" {
  description = "Public IP address of the Droplet"
  value       = digitalocean_droplet.ai_node.ipv4_address
}

output "litellm_endpoint" {
  description = "LiteLLM API endpoint"
  value       = "http://${digitalocean_droplet.ai_node.ipv4_address}:4000"
}