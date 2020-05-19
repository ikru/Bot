variable "tenant_id" {
  description = "Your Azure Tenant Id"
}
variable "subscription_id" {
  description = "Subscription to create a group under"
}
variable "bot_name" {
  description = "System name of the bot, all resources names will be prefixed with this name"
}
variable "default_location" {
  description = "Default location for most of resources. Those demanding specific resources are hardcoded"
}
variable "qnaluis_location" {
  description = "QnA/Luis is not available in Central Canada, so I had to create separate location for it"
}
