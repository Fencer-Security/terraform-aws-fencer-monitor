variable "fencer_endpoint_url" {
  type        = string
  description = "The Fencer Firehose HTTP endpoint URL. Copy it from the AWS Monitor page in the Fencer app."

  validation {
    condition     = startswith(var.fencer_endpoint_url, "https://")
    error_message = "fencer_endpoint_url must start with https://."
  }
}

variable "fencer_access_key" {
  type        = string
  description = "The Fencer access token. Generate it on the AWS Monitor page in the Fencer app. Pass it from a secrets manager or TF_VAR_fencer_access_key. Do not commit it."
  sensitive   = true

  validation {
    condition     = length(var.fencer_access_key) > 0
    error_message = "fencer_access_key must not be empty."
  }
}

variable "cloudwatch_log_group_names" {
  type        = list(string)
  description = "CloudWatch Logs log groups to stream to Fencer. The module creates one subscription filter per log group. Leave empty when the AWS service writes to the Firehose stream directly."
  default     = []

  validation {
    condition     = alltrue([for name in var.cloudwatch_log_group_names : length(name) > 0]) && length(var.cloudwatch_log_group_names) == length(distinct(var.cloudwatch_log_group_names))
    error_message = "cloudwatch_log_group_names entries must be non-empty and unique."
  }
}

variable "name_prefix" {
  type        = string
  description = "Prefix for all resource names."
  default     = "fencer-siem"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name_prefix)) && length(var.name_prefix) <= 29
    error_message = "name_prefix must start with a lowercase letter or digit, match ^[a-z0-9][a-z0-9-]*$, and contain at most 29 characters."
  }
}

variable "subscription_filter_pattern" {
  type        = string
  description = "Filter pattern for the subscription filters. Empty sends all events."
  default     = ""
}

variable "backup_expiration_days" {
  type        = number
  description = "Days before failed-delivery objects expire from the backup bucket."
  default     = 30

  validation {
    condition     = var.backup_expiration_days >= 1
    error_message = "backup_expiration_days must be at least 1."
  }
}

variable "error_log_retention_days" {
  type        = number
  description = "Retention in days for the Firehose error log group."
  default     = 7

  validation {
    condition     = var.error_log_retention_days >= 1
    error_message = "error_log_retention_days must be at least 1."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all taggable resources."
  default     = {}
}
