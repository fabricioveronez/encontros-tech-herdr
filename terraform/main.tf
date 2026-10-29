locals {
  name = "${var.project_name}-${var.environment}"
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "network" {
  source             = "./modules/network"
  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "security" {
  source                = "./modules/security"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  container_port        = var.container_port
  allowed_ingress_cidrs = var.allowed_ingress_cidrs
}

module "database" {
  source                            = "./modules/database"
  name                              = local.name
  database_subnet_ids               = module.network.database_subnet_ids
  database_security_group_id        = module.security.database_security_group_id
  db_name                           = var.db_name
  db_username                       = var.db_username
  db_engine_version                 = var.db_engine_version
  db_instance_class                 = var.db_instance_class
  db_allocated_storage              = var.db_allocated_storage
  db_max_allocated_storage          = var.db_max_allocated_storage
  db_multi_az                       = var.db_multi_az
  db_backup_retention_period        = var.db_backup_retention_period
  db_deletion_protection            = var.db_deletion_protection
  db_skip_final_snapshot            = var.db_skip_final_snapshot
  db_secret_recovery_window_in_days = var.db_secret_recovery_window_in_days
}

module "alb" {
  source                = "./modules/alb"
  name                  = local.name
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id
  container_port        = var.container_port
  health_check_path     = var.health_check_path
  deregistration_delay  = var.deregistration_delay
}

module "ecs" {
  source                            = "./modules/ecs"
  name                              = local.name
  aws_region                        = var.aws_region
  app_subnet_ids                    = module.network.app_subnet_ids
  app_security_group_id             = module.security.app_security_group_id
  target_group_arn                  = module.alb.target_group_arn
  database_url_secret_arn           = module.database.database_url_secret_arn
  container_image                   = var.container_image
  container_port                    = var.container_port
  task_cpu                          = var.task_cpu
  task_memory                       = var.task_memory
  cpu_architecture                  = var.cpu_architecture
  desired_count                     = var.desired_count
  web_concurrency                   = var.web_concurrency
  extra_environment                 = var.extra_environment
  log_retention_days                = var.log_retention_days
  enable_container_insights         = var.enable_container_insights
  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  # Wait for the listener and the initial secret value before starting tasks.
  depends_on = [module.alb, module.database]
}
