output "region" {
  value = var.region
}

output "app_instance_id" {
  value = aws_instance.app.id
}

output "k6_instance_id" {
  value = aws_instance.k6.id
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}

output "results_bucket" {
  value = aws_s3_bucket.results.bucket
}
