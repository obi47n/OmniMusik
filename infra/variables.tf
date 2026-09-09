variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "omnimusik"
}

variable "web_origin" {
  description = "Origin the web client is served from. Used for CORS and as an OAuth callback."
  type        = string
  default     = "http://localhost:5173"
}

variable "ios_redirect_scheme" {
  description = "Custom URL scheme the iOS client redirects back to after sign-in."
  type        = string
  default     = "omnimusik"
}

variable "db_instance_class" {
  description = "RDS instance class. db.t4g.micro is the cheapest that stays in the burstable family."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Gigabytes of storage for the database."
  type        = number
  default     = 20
}

variable "app_runner_cpu" {
  description = "App Runner vCPU allocation."
  type        = string
  default     = "0.25 vCPU"
}

variable "app_runner_memory" {
  description = "App Runner memory allocation."
  type        = string
  default     = "0.5 GB"
}

variable "container_image_tag" {
  description = "Tag in ECR that App Runner should deploy."
  type        = string
  default     = "latest"
}

variable "enable_sign_in_with_apple" {
  description = <<-EOT
    Whether to wire Sign in with Apple into the user pool as a federated identity
    provider. Left off by default because it needs a Services ID, a team ID, a key
    ID and a .p8 private key, and the whole stack must be applyable without them --
    Cognito's own email and password sign-in works from day one either way.
  EOT
  type        = bool
  default     = false
}

variable "apple_services_id" {
  description = "Apple Services ID, used as the OAuth client ID. Only read when enable_sign_in_with_apple is true."
  type        = string
  default     = ""
}

variable "apple_team_id" {
  description = "Apple Developer team ID."
  type        = string
  default     = ""
}

variable "apple_key_id" {
  description = "Key ID of the Sign in with Apple private key."
  type        = string
  default     = ""
}

variable "apple_private_key" {
  description = "Contents of the .p8 private key. Pass via TF_VAR_apple_private_key, never a committed tfvars file."
  type        = string
  default     = ""
  sensitive   = true
}
