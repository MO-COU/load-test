variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "app_instance_type" {
  description = "앱 + MySQL + Redis"
  type        = string
  default     = "c5.2xlarge"
}

variable "k6_instance_type" {
  description = "부하 생성기. VU 20,000 의 메모리가 실제 제약이라 앱 서버보다 한 단계 크다"
  type        = string
  default     = "c5.4xlarge"
}

variable "repo_url" {
  type    = string
  default = "https://github.com/MO-COU/load-test.git"
}

variable "root_volume_gb" {
  type    = number
  default = 30
}
