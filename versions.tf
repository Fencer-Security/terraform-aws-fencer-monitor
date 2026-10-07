terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.56.0" # tag_field_specification on aws_flow_log
    }
  }
}
