# Everything the clients need in order to be configured.
#
# These are the values that go into CognitoConfiguration.swift and the web client's
# .env.local. None of them are secret: the app client is public and secured by PKCE.

output "cognito_domain" {
  description = "Hosted UI domain. Goes into CognitoConfiguration.domain and VITE_COGNITO_DOMAIN."
  value       = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "cognito_app_client_id" {
  description = "Public app client ID, shared by both clients."
  value       = aws_cognito_user_pool_client.app.id
}

output "cognito_issuer_uri" {
  description = "Token issuer. The API discovers the JWKS endpoint from this."
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "api_url" {
  description = "Public URL of the service. Goes into VITE_API_BASE_URL."
  value       = "https://${aws_apprunner_service.api.service_url}"
}

output "ecr_repository_url" {
  description = "Push the API image here; App Runner redeploys on a new :latest."
  value       = aws_ecr_repository.api.repository_url
}

output "database_secret_arn" {
  description = "Secrets Manager entry holding the database credentials."
  value       = aws_secretsmanager_secret.database.arn
}

output "sign_in_with_apple_enabled" {
  description = "Whether the pool federates Sign in with Apple in this deployment."
  value       = var.enable_sign_in_with_apple
}
