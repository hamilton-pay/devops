variable "aws_region" {
  type    = string
  default = "us-west-2"
}


variable "mailgun_secrets" {
  type = map(string)
}

variable "cloudfare_secrets" {
  type = map(string)
}
variable "stripe_secrets" {
  type = map(string)
}

variable "plaid_secrets" {
  type = map(string)
}