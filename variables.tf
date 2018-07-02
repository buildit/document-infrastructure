variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "us-east-1"
}

variable "az_count" {
  description = "Number of AZs to cover in a given AWS region"
  default     = "2"
}

variable "default_cpu" {
  description = "Fargate instance CPU units to provision (1 vCPU = 1024 CPU units)"
  default     = "256"
}

variable "default_memory" {
  description = "Fargate instance memory to provision (in MiB)"
  default     = "512"
}

variable "default_count" {
  description = "Number of docker containers to run"
  default     = 1
}