variable "document_repository_image" {
  description = "Docker image to run in the ECS cluster"
  default     = "builditdigital/document-repository-web:latest"
}

variable "document_repository_port" {
  description = "Port exposed by the docker image to redirect traffic to"
  default     = 8080
}

resource "aws_iam_role" "document_repository_task_execution_role" {
  name = "document_repository_task_execution_role"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "document_repository_policy_cloudwatch" {
  role = "${aws_iam_role.document_repository_task_execution_role.id}"
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_ecs_task_definition" "document_repository" {
  family                   = "document_repository"
  execution_role_arn       = "${aws_iam_role.document_repository_task_execution_role.arn}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.default_cpu}"
  memory                   = "${var.default_memory}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.default_cpu},
    "image": "${var.document_repository_image}",
    "memory": ${var.default_memory},
    "name": "document_repository",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.document_repository_port},
        "hostPort": ${var.document_repository_port}
      }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${aws_cloudwatch_log_group.document_repository.name}",
            "awslogs-region": "${var.aws_region}",
            "awslogs-stream-prefix": "/ecs"
        }
    },
    "environment": [
      {
        "name": "cloud.aws.credentials.accessKey",
        "value": ""
      },
      {
        "name": "cloud.aws.credentials.secretKey",
        "value": ""
      },
      {
        "name": "cloud.aws.es.domain",
        "value": ""
      }
    ]
  }
]
DEFINITION
}

resource "aws_ecs_service" "document_repository" {
  name            = "document_repository_service"
  cluster         = "${aws_ecs_cluster.main.id}"
  task_definition = "${aws_ecs_task_definition.document_repository.arn}"
  desired_count   = "${var.default_count}"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = ["${aws_security_group.document_repository_ecs_tasks.id}"]
    subnets         = ["${aws_subnet.private.*.id}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.document_repository_target_group.id}"
    container_name   = "document_repository"
    container_port   = "${var.document_repository_port}"
  }

  depends_on = [
    "aws_alb_listener.app",
  ]
}

# Traffic to the ECS Cluster should only come from the ALB
resource "aws_security_group" "document_repository_ecs_tasks" {
  name        = "document_repository_ecs_tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.document_repository_port}"
    to_port         = "${var.document_repository_port}"
    security_groups = ["${aws_security_group.lb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_cloudwatch_log_group" "document_repository" {
  name              = "/ecs/document_repository"
}

resource "aws_cloudwatch_log_stream" "document_repository" {
  name           = "document_repository"
  log_group_name = "${aws_cloudwatch_log_group.document_repository.name}"
}

resource "aws_alb_listener_rule" "document_repository" {
  listener_arn = "${aws_alb_listener.app.arn}"
  priority     = 99

  action {
    type             = "forward"
    target_group_arn = "${aws_alb_target_group.document_repository_target_group.arn}"
  }

  condition {
    field  = "path-pattern"
    values = ["/repository"]
  }
}

resource "aws_alb_target_group" "document_repository_target_group" {
  name        = "document-repository-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${aws_vpc.main.id}"
  target_type = "ip"

  health_check {
    path                = "/repository/health"
  }
}