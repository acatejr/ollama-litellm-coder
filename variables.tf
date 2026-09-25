variable "do_token" {
  description = "DigitalOcean Personal Access Token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region"
  type        = string
  default     = "sfo3"
}

variable "droplet_size" {
  description = "Droplet size (8GB RAM / 4 vCPUs offers optimal headroom for qwen2.5-coder:3b)"
  type        = string
  default     = "s-4vcpu-8gb" # Updated from s-2vcpu-4gb
}

variable "ssh_key_names" {
  description = "Names of SSH keys already in your DigitalOcean account that may log in as root"
  type        = list(string)
  default     = ["acatejr@mbp", "acatejr@thalweg"]

  validation {
    condition     = length(var.ssh_key_names) > 0
    error_message = "ssh_key_names must contain at least one key name."
  }
}

variable "litellm_master_key" {
  description = "Master API key for LiteLLM (set via TF_VAR_litellm_master_key)"
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.litellm_master_key, "sk-")
    error_message = "litellm_master_key must start with \"sk-\" (required by LiteLLM)."
  }

  validation {
    condition     = length(regexall("['\\s]", var.litellm_master_key)) == 0
    error_message = "litellm_master_key must not contain single quotes or whitespace."
  }
}
