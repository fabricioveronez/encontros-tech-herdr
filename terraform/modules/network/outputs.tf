output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = [for az in var.availability_zones : aws_subnet.public[az].id] }
output "app_subnet_ids" { value = [for az in var.availability_zones : aws_subnet.app[az].id] }
output "database_subnet_ids" { value = [for az in var.availability_zones : aws_subnet.database[az].id] }
