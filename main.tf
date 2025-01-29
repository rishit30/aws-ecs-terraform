# Configure AWS Provider
provider "aws" {
  region = "us-east-1"
}

# VPC Configuration
resource "aws_vpc" "testing-app_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "testing-app-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "testing-app_igw" {
  vpc_id = aws_vpc.testing-app_vpc.id

  tags = {
    Name = "testing-app-igw"
  }
}

# Public Subnets
resource "aws_subnet" "testing-app_public_1" {
  vpc_id            = aws_vpc.testing-app_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "testing-app-public-1"
  }
}

resource "aws_subnet" "testing-app_public_2" {
  vpc_id            = aws_vpc.testing-app_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "testing-app-public-2"
  }
}

# Route Table
resource "aws_route_table" "testing-app_public_rt" {
  vpc_id = aws_vpc.testing-app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.testing-app_igw.id
  }

  tags = {
    Name = "testing-app-public-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "testing-app_public_1" {
  subnet_id      = aws_subnet.testing-app_public_1.id
  route_table_id = aws_route_table.testing-app_public_rt.id
}

resource "aws_route_table_association" "testing-app_public_2" {
  subnet_id      = aws_subnet.testing-app_public_2.id
  route_table_id = aws_route_table.testing-app_public_rt.id
}

# Security Group for ALB
resource "aws_security_group" "testing-app_alb_sg" {
  name        = "testing-app-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.testing-app_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "testing-app-alb-sg"
  }
}

# Security Group for ECS Tasks
resource "aws_security_group" "testing-app_ecs_sg" {
  name        = "testing-app-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.testing-app_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.testing-app_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "testing-app-ecs-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "testing-app_alb" {
  name               = "testing-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.testing-app_alb_sg.id]
  subnets           = [aws_subnet.testing-app_public_1.id, aws_subnet.testing-app_public_2.id]

  tags = {
    Name = "testing-app-alb"
  }
}

# Target Group
resource "aws_lb_target_group" "testing-app_tg" {
  name        = "testing-app-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.testing-app_vpc.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher            = "200"
    path               = "/"
    port               = "traffic-port"
    protocol           = "HTTP"
    timeout            = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "testing-app-tg"
  }
}

# Listener
resource "aws_lb_listener" "testing-app_listener" {
  load_balancer_arn = aws_lb.testing-app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.testing-app_tg.arn
  }
}

# ECR Repository
resource "aws_ecr_repository" "testing-app_repo" {
  name = "testing-app"
}

# ECS Cluster
resource "aws_ecs_cluster" "testing-app_cluster" {
  name = "testing-app-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "testing-app_task" {
  family                   = "testing-app-task"
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                     = "256"
  memory                  = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "testing-app-container"
      image = "${aws_ecr_repository.testing-app_repo.repository_url}:latest"
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/testing-app"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "testing-app_logs" {
  name              = "/ecs/testing-app"
  retention_in_days = 30
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "testing-app-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach the required policies to the IAM Role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_cloudwatch_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

# ECS Service
resource "aws_ecs_service" "testing-app_service" {
  name            = "testing-app-service"
  cluster         = aws_ecs_cluster.testing-app_cluster.id
  task_definition = aws_ecs_task_definition.testing-app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.testing-app_public_1.id, aws_subnet.testing-app_public_2.id]
    security_groups = [aws_security_group.testing-app_ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.testing-app_tg.arn
    container_name   = "testing-app-container"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.testing-app_listener]
}

# Outputs
output "ecr_repository_url" {
  value = aws_ecr_repository.testing-app_repo.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.testing-app_cluster.name
}

output "alb_dns_name" {
  value = aws_lb.testing-app_alb.dns_name
  description = "The DNS name of the load balancer"
}
