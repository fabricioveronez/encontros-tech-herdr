variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "encontros-tech"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "az_count" {
  type    = number
  default = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 10 && floor(var.az_count) == var.az_count
    error_message = "az_count must be an integer between 2 and 10."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "allowed_ingress_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "container_image" {
  type        = string
  description = "Public Docker Hub image including an immutable tag or digest."
}

variable "container_port" {
  type    = number
  default = 8000
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}

variable "cpu_architecture" {
  type    = string
  default = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "desired_count" {
  type    = number
  default = 2

  validation {
    condition     = var.desired_count >= 1 && floor(var.desired_count) == var.desired_count
    error_message = "desired_count must be a positive integer."
  }
}

variable "web_concurrency" {
  type    = number
  default = 2
}

variable "extra_environment" {
  type    = map(string)
  default = {}

  validation {
    condition     = length(setintersection(toset(keys(var.extra_environment)), toset(["PORT", "WEB_CONCURRENCY", "LOG_FORMAT", "DATABASE_URL"]))) == 0
    error_message = "extra_environment cannot override PORT, WEB_CONCURRENCY, LOG_FORMAT or DATABASE_URL."
  }
}

variable "health_check_path" {
  type    = string
  default = "/metrics"
}

variable "health_check_grace_period_seconds" {
  type    = number
  default = 60
}

variable "deregistration_delay" {
  type    = number
  default = 30
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "enable_container_insights" {
  type    = bool
  default = false
}

variable "db_name" {
  type    = string
  default = "encontros_tech"
}

variable "db_username" {
  type    = string
  default = "app_user"
}

variable "db_engine_version" {
  type    = string
  default = "16"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_max_allocated_storage" {
  type    = number
  default = 100
}

variable "db_multi_az" {
  type    = bool
  default = true
}

variable "db_backup_retention_period" {
  type    = number
  default = 7
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}

variable "db_secret_recovery_window_in_days" {
  type    = number
  default = 0
}
