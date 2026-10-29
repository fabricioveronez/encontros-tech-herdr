resource "aws_lb" "this" {
  name               = substr("${var.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  tags               = { Name = "${var.name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name                 = length("${var.name}-tg") <= 32 ? "${var.name}-tg" : null
  name_prefix          = length("${var.name}-tg") > 32 ? substr(var.name, 0, 6) : null
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = var.deregistration_delay

  health_check {
    path    = var.health_check_path
    matcher = "200"
  }

  tags = { Name = "${var.name}-app" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
