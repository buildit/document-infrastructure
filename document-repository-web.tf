variable "docuent_repository_image" {
  description = "Docker image to run in the ECS cluster"
  default     = "builditdigital/document-repository-web:latest"
}

variable "docuent_repository_port" {
  description = "Port exposed by the docker image to redirect traffic to"
  default     = 8080
}

resource "aws_ecs_task_definition" "document_repository" {
  family                   = "app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${var.default_cpu}"
  memory                   = "${var.default_memory}"

  container_definitions = <<DEFINITION
[
  {
    "cpu": ${var.default_cpu},
    "image": "${var.docuent_repository_image}",
    "memory": ${var.default_memory},
    "name": "app",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": ${var.docuent_repository_port},
        "hostPort": ${var.docuent_repository_port}
      }
    ],
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
        "name": "cloud.aws.region",
        "value": "us-east-1"
      },
      {
        "name": "cloud.aws.s3.bucket",
        "value": "documents-spike-dev"
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
    security_groups = ["${aws_security_group.docuent_repository_ecs_tasks.id}"]
    subnets         = ["${aws_subnet.private.*.id}"]
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.app.id}"
    container_name   = "app"
    container_port   = "${var.docuent_repository_port}"
  }

  depends_on = [
    "aws_alb_listener.front_end",
  ]
}

# Traffic to the ECS Cluster should only come from the ALB
resource "aws_security_group" "docuent_repository_ecs_tasks" {
  name        = "docuent_repository_ecs_tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${aws_vpc.main.id}"

  ingress {
    protocol        = "tcp"
    from_port       = "${var.docuent_repository_port}"
    to_port         = "${var.docuent_repository_port}"
    security_groups = ["${aws_security_group.lb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}