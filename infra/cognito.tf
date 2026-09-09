# Identity.
#
# A Cognito user pool with Sign in with Apple federated in when credentials are
# available. That layering is the point: Sign in with Apple stays the intended
# primary button, but the clients are decoupled from whether it is provisioned yet.
# Email and password work from the first apply, and turning SIWA on later changes
# nothing in either client.

resource "aws_cognito_user_pool" "main" {
  name = "${var.project}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Apple may withhold an email entirely through Hide My Email, so the attribute
  # cannot be required. The subject claim is the identity; see AppUser on the server.
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project}-${data.aws_caller_identity.current.account_id}"
  user_pool_id = aws_cognito_user_pool.main.id
}

data "aws_caller_identity" "current" {}

resource "aws_cognito_identity_provider" "apple" {
  count = var.enable_sign_in_with_apple ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "SignInWithApple"
  provider_type = "SignInWithApple"

  provider_details = {
    client_id                     = var.apple_services_id
    team_id                       = var.apple_team_id
    key_id                        = var.apple_key_id
    private_key                   = var.apple_private_key
    authorize_scopes              = "email name"
    attributes_url_add_attributes = "false"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}

resource "aws_cognito_user_pool_client" "app" {
  name         = "${var.project}-clients"
  user_pool_id = aws_cognito_user_pool.main.id

  # No secret. Neither a native binary nor a browser can keep one, so both clients
  # are public and PKCE is what actually secures the code exchange.
  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  # One client serves both the app and the web client. They run the same flow
  # against the same pool and differ only in redirect URI.
  callback_urls = [
    "${var.web_origin}/callback",
    "${var.ios_redirect_scheme}://auth",
  ]
  logout_urls = [
    var.web_origin,
    "${var.ios_redirect_scheme}://auth",
  ]

  supported_identity_providers = concat(
    ["COGNITO"],
    var.enable_sign_in_with_apple ? ["SignInWithApple"] : []
  )

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # A wrong username or password should not be distinguishable from a username that
  # does not exist, or the endpoint becomes an account-enumeration oracle.
  prevent_user_existence_errors = "ENABLED"

  depends_on = [aws_cognito_identity_provider.apple]
}
