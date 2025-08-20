# AWS SNS for Grafana SMS Alerts (Terraform)

This Terraform config creates an SNS topic for Grafana alerts, subscribes your phone via SMS, and (optionally) creates a publish-only IAM user for Grafana.

## What it does
- Creates an SNS topic (default: `sns-grafana-alerts`).
- Subscribes your phone number via SMS (E.164 format, e.g., `+15551234567`).
- Optionally sets account-level SNS SMS preferences (type, spend limit, etc.).
- Creates an IAM user + access keys with `sns:Publish` on just this topic.

## Setup
1. Copy `sns-config.yaml.example` to `sns-config.yaml` and edit:
   - `region`: AWS region (e.g., `us-west-2`).
   - `topic_name`: Topic name.
   - `phone_number`: Your phone in E.164 format.
   - `create_iam_user`: `true` to generate keys for Grafana.
   - Optional SMS prefs: `default_sms_type`, `monthly_spend_limit`, etc.

2. Init + apply:
   - `terraform init`
   - `terraform apply`

## Outputs
- `sns_topic_arn`: ARN to use in Grafana’s Amazon SNS contact point.
- `access_key_id` / `secret_access_key` (sensitive): Use these in Grafana if `create_iam_user = true`.
- `grafana_contact_point_hint` (sensitive): Handy map of values for Grafana.

## Grafana contact point
In Grafana (Alerting > Contact points):
- Type: Amazon SNS
- Region: match `region`
- Topic ARN: `sns_topic_arn`
- Access Key / Secret: use outputs if you created the IAM user

## Notes
- SMS delivery limits/costs: consider `monthly_spend_limit` and `default_sms_type = Transactional`.
- US long codes may require A2P 10DLC registration for high volume. For basic alerts, the default settings usually work, but consult AWS SNS SMS docs if messages don’t deliver as expected.
- The `aws_sns_sms_preferences` resource sets account-level SMS preferences. Only set values you need.
