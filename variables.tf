variable "aws_profile" {
  type    = string
  default = "infra"
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "state_s3_bucket" {
    type = string 
}

variable "state_s3_bucket_region" {
    type = string 
}

variable "state_s3_bucket_key" {
    type = string 
}
