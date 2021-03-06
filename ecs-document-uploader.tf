locals {
  document_uploader_image                = "${var.document_uploader_image_name}:${var.document_uploader_image_version}"
  document_uploader_alb_path             = "${var.document_uploader_base_path}*"
  document_uploader_alb_health_check_url = "${var.document_uploader_base_path}/${var.document_uploader_alb_health_check_path}"
  document_uploader_iam_user_name = "${var.document_uploader_app_name}-${var.env}-user"
}

variable "document_uploader_app_name" {
  default = "document_uploader"
}

variable "document_uploader_image_name" {
  default = "builditdigital/document-uploader"
}

variable "document_uploader_image_version" {
  default = "latest"
}

variable "document_uploader_image_port" {
  default = 8080
}

variable "document_uploader_base_path" {
  default = "/uploader"
}

variable "document_uploader_alb_health_check_path" {
  default = "/health"
}

variable "document_uploader_port" {
  description = "Port exposed by the docker image to redirect traffic to"
  default     = 8080
}

resource "aws_iam_role" "document_uploader_task_execution_role" {
  name = "${var.document_uploader_app_name}_task_execution_role_${var.env}"

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

resource "aws_iam_user_policy_attachment" "document_uploader_policy_s3full" {
  user       = "${aws_iam_user.uploader.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "document_uploader_policy_cloudwatch" {
  role       = "${aws_iam_role.document_uploader_task_execution_role.id}"
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_user" "uploader" {
  name = "${local.document_uploader_iam_user_name}"
}

resource "aws_iam_access_key" "uploader" {
  user = "${aws_iam_user.uploader.name}"
}

resource "aws_ecs_task_definition" "document_uploader" {
  family                   = "${var.document_uploader_app_name}"
  network_mode             = "awsvpc"
  execution_role_arn       = "${aws_iam_role.document_uploader_task_execution_role.arn}"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.default_ecs_cpu}"
  memory                   = "${var.default_ecs_memory}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.default_ecs_cpu},
    "image": "${local.document_uploader_image}",
    "memory": ${var.default_ecs_memory},
    "name": "document_uploader",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.document_uploader_port},
        "hostPort": ${var.document_uploader_port}
      }
    ],
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
            "awslogs-group": "${aws_cloudwatch_log_group.document_uploader.name}",
            "awslogs-region": "${var.region}",
            "awslogs-stream-prefix": "/ecs"
        }
    },
    "environment": [
      {
        "name": "cloud.aws.credentials.accessKey",
        "value": "${aws_iam_access_key.uploader.id}"
      },
      {
        "name": "cloud.aws.credentials.secretKey",
        "value": "${aws_iam_access_key.uploader.secret}"
      },
      {
        "name": "cloud.aws.s3.bucket",
        "value": "${var.storage_bucket}-${var.env}"
      },
      {
        "name": "cloud.aws.region",
        "value": "${var.region}"
      }
    ]
  }
]
DEFINITION
}

resource "aws_cloudwatch_log_group" "document_uploader" {
  name = "/ecs/${var.document_uploader_app_name}_${var.env}"
}

resource "aws_cloudwatch_log_stream" "document_uploader" {
  name           = "${var.document_uploader_app_name}"
  log_group_name = "${aws_cloudwatch_log_group.document_uploader.name}"
}

resource "aws_ecs_service" "document_uploader" {
  name            = "${var.document_uploader_app_name}_service"
  cluster         = "${aws_ecs_cluster.main.id}"
  task_definition = "${aws_ecs_task_definition.document_uploader.arn}"
  desired_count   = "${var.default_ecs_count}"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = ["${aws_security_group.document_uploader_ecs_tasks.id}"]
    subnets         = ["${aws_subnet.private.*.id}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.document_uploader_target_group.id}"
    container_name   = "${var.document_uploader_app_name}"
    container_port   = "${var.document_uploader_port}"
  }

  depends_on = [
    "aws_alb_listener.app",
  ]
}

# Traffic to the ECS Cluster should only come from the ALB
resource "aws_security_group" "document_uploader_ecs_tasks" {
  name        = "${var.document_uploader_app_name}_ecs_tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.document_uploader_port}"
    to_port         = "${var.document_uploader_port}"
    security_groups = ["${aws_security_group.lb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_alb_target_group" "document_uploader_target_group" {
  name        = "document-uploader-${var.env}"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${aws_vpc.main.id}"
  target_type = "ip"

  health_check {
    path = "${local.document_uploader_alb_health_check_url}"
  }
}

resource "aws_alb_listener_rule" "uploader" {
  listener_arn = "${aws_alb_listener.app.arn}"
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = "${aws_alb_target_group.document_uploader_target_group.arn}"
  }

  condition {
    field  = "path-pattern"
    values = ["${local.document_uploader_alb_path}"]
  }
}
