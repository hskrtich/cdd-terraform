locals {
  vpc_id = "vpc-00000000"
  subnet_ids = [
    "subnet-00000000000000",
    "subnet-11111111111111",
  ]
  cluster_id = "ecs-cluster-name"

  service_list = {
    "pdf-converter-website" = {
      desired_count  = 2
      container_port = 80
      task_cpu       = 0.5
      task_memory    = "256mb"
    },
    "pdf-converter-svg" = {
      desired_count  = 4
      container_port = 80
      task_cpu       = 0.5
      task_memory    = "256mb"
    },
  }

  whitelist_access = [
    "10.0.0.0/24",        # Production - AWS
    "123.123.123.123/32", # Quality - Datacenter
  ]
}


# Create an ECR repository
resource "aws_ecr_repository" "this" {
  for_each = local.service_list

  name = each.key
}

# Define the ECS Task Definition
resource "aws_ecs_task_definition" "this" {
  for_each = local.service_list

  family                   = each.key
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = each.value.task_cpu
  memory                   = each.value.task_memory

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.this[each.key].repository_url}:latest"
      cpu       = each.value.task_cpu
      memory    = each.value.task_memory
      essential = true
      portMappings = [
        {
          containerPort = each.value.container_port
          hostPort      = each.value.container_port
        }
      ]
    }
  ])
}

# Define an ECS Service
resource "aws_ecs_service" "app_service" {
  for_each = local.service_list

  name            = each.key
  cluster         = local.cluster_id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = local.subnet_ids
    security_groups = [aws_security_group.app[each.key].id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this[each.key].arn
    container_name   = "app"
    container_port   = each.value.container_port
  }
  depends_on = [aws_lb_listener.this]
}

# Create a Security Group for the app on the ECS service
resource "aws_security_group" "app" {
  for_each = local.service_list

  name   = "${each.key}_app_${each.value.container_port}"
  vpc_id = local.vpc_id

  ingress {
    from_port       = each.value.container_port
    to_port         = each.value.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb[each.key].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a Security Group for the ALB
resource "aws_security_group" "alb" {
  for_each = local.service_list

  name   = "${each.key}_alb_443"
  vpc_id = local.vpc_id

  # Allow HTTPS traffic from whitelisted IP addresses only
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.whitelist_access
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create an ALB
resource "aws_lb" "this" {
  for_each = local.service_list

  name               = "${each.key}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[each.key].id]
  subnets            = local.subnet_ids
}

# Create an ALB Target Group
resource "aws_lb_target_group" "this" {
  for_each = local.service_list

  name        = "app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"
}

# Create an SSL cert for use in ALB
module "ssl_cert" {
  source  = "cloudposse/acm-request-certificate/aws"
  version = "v0.18.0"

  domain_name = "example.com"
  ttl         = "300"

  process_domain_validation_options = true
  subject_alternative_names         = ["*.example.com"]
}

# Create an ALB Listener for HTTPS (port 443) with SSL certificate
resource "aws_lb_listener" "this" {
  for_each = local.service_list

  load_balancer_arn = aws_lb.this[each.key].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-3-2021-06" # Latest SSL Policy

  certificate_arn = module.ssl_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}
