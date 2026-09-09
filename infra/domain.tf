# A domain of our own in front of the web client.
#
# CloudFront's *.cloudfront.net name is assigned, not chosen, and cannot be renamed;
# the way to change the link is to put a domain in front of it. Everything here is
# gated on `web_domain` so the stack applies unchanged while the domain does not
# exist yet -- registering one is a purchase, which is a person's action.
#
# The hosted zone is Terraform's, whichever registrar sells the name. Route 53
# refused to register for this account -- a hold it places on new accounts, lifted
# only by a support case -- so the domain may well come from elsewhere, and a
# registrar elsewhere simply needs its nameservers pointed at this zone's four NS
# records (`web_nameservers` below). Had Route 53 registered it, it would have made
# a zone of its own; that one would then be deleted and this one used, so there is
# exactly one zone per name and Terraform owns it.
#
# The certificate is validated over DNS with records Terraform writes into that
# zone, so there is nothing to click. It lives in us-east-1 because CloudFront
# accepts certificates from nowhere else; the provider already is.
#
# The API keeps its ECS-assigned hostname. Express Mode has no way to present a
# certificate for a custom name, so `api.<domain>` would need a CloudFront
# distribution of its own in front of the service. Deliberately not done here.

variable "web_domain" {
  description = "Apex domain for the web client, e.g. \"omnimusikofficial.app\". Empty leaves CloudFront on its default name and creates none of this."
  type        = string
  default     = ""
}

locals {
  domain_enabled = var.web_domain != ""
  web_hostnames  = local.domain_enabled ? [var.web_domain, "www.${var.web_domain}"] : []
  # What the clients and the API treat as the web origin once the domain is live.
  web_custom_origins = [for h in local.web_hostnames : "https://${h}"]
}

resource "aws_route53_zone" "web" {
  count   = local.domain_enabled ? 1 : 0
  name    = var.web_domain
  comment = "OmniMusik web client"
}

resource "aws_acm_certificate" "web" {
  count = local.domain_enabled ? 1 : 0

  domain_name               = var.web_domain
  subject_alternative_names = ["www.${var.web_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project}-web" }
}

resource "aws_route53_record" "web_cert_validation" {
  for_each = local.domain_enabled ? {
    for dvo in aws_acm_certificate.web[0].domain_validation_options :
    dvo.domain_name => { name = dvo.resource_record_name, type = dvo.resource_record_type, record = dvo.resource_record_value }
  } : {}

  zone_id         = aws_route53_zone.web[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "web" {
  count = local.domain_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.web[0].arn
  validation_record_fqdns = [for r in aws_route53_record.web_cert_validation : r.fqdn]
}

# Apex and www both point at the distribution. Alias records rather than CNAMEs,
# because a CNAME is not allowed at an apex and an alias costs nothing per query.
resource "aws_route53_record" "web_a" {
  for_each = toset(local.web_hostnames)

  zone_id = aws_route53_zone.web[0].zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.web.domain_name
    zone_id                = aws_cloudfront_distribution.web.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "web_aaaa" {
  for_each = toset(local.web_hostnames)

  zone_id = aws_route53_zone.web[0].zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.web.domain_name
    zone_id                = aws_cloudfront_distribution.web.hosted_zone_id
    evaluate_target_health = false
  }
}

output "web_nameservers" {
  description = "Set these as the domain's nameservers at the registrar. Empty until web_domain is set."
  value       = local.domain_enabled ? aws_route53_zone.web[0].name_servers : []
}

output "web_custom_url" {
  description = "The web client on its own domain, once web_domain is set and applied."
  value       = local.domain_enabled ? "https://${var.web_domain}" : null
}
