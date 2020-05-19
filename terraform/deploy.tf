# export https_proxy=
# tfpath="$PWD/terraform"; terraform() { "$tfpath" "$@"; }
# az login 
# terraform plan
# terraform apply
# kubectl get nodes
provider "azuread" {
  version = "~> 0.8"

  tenant_id = var.tenant_id
  subscription_id = var.subscription_id
}
provider "azurerm" {
  version = "=2.10.0"
  features {}
  
  tenant_id = var.tenant_id
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" { }
output "account_id" { value = data.azurerm_client_config.current.client_id }

# ***** APP REGISTRATION *****

resource "azuread_application" "app" {
  name                       = "${var.bot_name}_app"
  available_to_other_tenants = false
  oauth2_allow_implicit_flow = true
}
resource "azuread_service_principal" "sp" {
  application_id = azuread_application.app.application_id
}
resource "azuread_service_principal_password" "spp" {
  service_principal_id = azuread_service_principal.sp.id
  value                = "VT=uSgbTanZhyz@%nL9Hpd+Tfay_MRV#"
  end_date             = "2099-01-01T01:02:03Z"
}

# ***** RESOURCE GROUP *****

resource "azurerm_resource_group" rg {
  name     = upper(var.bot_name)
  location = var.default_location
}

# ***** RND STRING FOR UNIQUE NAMES *****

resource "random_string" "rnd" {
  length = 4 
  special = false 
  upper = false
}

# ***** APPINSIGHTS *****

resource "azurerm_application_insights" "appinsights" {
  name                = "${var.bot_name}-appinsights"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}
resource "azurerm_application_insights_api_key" "appinsightsapikey" {
  name                    = "${var.bot_name}-appinsightsapikey"
  application_insights_id = azurerm_application_insights.appinsights.id
  read_permissions        = ["aggregate", "api", "draft", "extendqueries", "search"]
}

# ***** WEB APP *****

resource "azurerm_app_service_plan" "asp" {
  name                = "${var.bot_name}-appsvc-plan"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_app_service" "as" {
  name                = "${var.bot_name}-appsvc"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.asp.id

  identity {
    type = "SystemAssigned"
  }
  site_config {
    always_on = true
  }

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.appinsights.instrumentation_key
  }
}

data "azuread_service_principal" "as_principal" {
  display_name = azurerm_app_service.as.name
  depends_on   = [azurerm_app_service.as]
}

# ***** WEB APP BOT *****

resource "azurerm_bot_web_app" webappbot {
  name                                  = "${var.bot_name}-bot-${random_string.rnd.id}"
  location                              = "global"
  resource_group_name                   = azurerm_resource_group.rg.name
  sku                                   = "F0"
  microsoft_app_id                      = azuread_application.app.application_id
  endpoint                              = "https://${azurerm_app_service.as.name}.azurewebsites.net"
  developer_app_insights_api_key        = azurerm_application_insights_api_key.appinsightsapikey.api_key
  developer_app_insights_application_id = azurerm_application_insights.appinsights.app_id
}

resource "azurerm_bot_channel_directline" dl {
  bot_name            = azurerm_bot_web_app.webappbot.name
  location            = azurerm_bot_web_app.webappbot.location
  resource_group_name = azurerm_resource_group.rg.name

  site {
    name    = "default"
    enabled = true
  }
}

# ***** COSMOS *****

resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "${var.bot_name}-cosmos"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  enable_automatic_failover = true

  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 10
    max_staleness_prefix    = 200
  }

  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
  }
}

# ***** STORAGE *****

resource "azurerm_storage_account" "storage" {
  name                     = "${replace(lower(var.bot_name), "-", "")}storage"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

# ***** TRANSLATION *****

resource "azurerm_cognitive_account" "tran" {
  name                  = "${var.bot_name}-tran"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  kind                  = "TextTranslation"

  sku_name = "S1"
}

# ***** LUIS *****

resource "azurerm_cognitive_account" "luis" {
  name                  = "${var.bot_name}-luis"
  location              = var.qnaluis_location
  resource_group_name   = azurerm_resource_group.rg.name
  kind                  = "LUIS.Authoring"

  sku_name = "F0"
}

# ***** QNA *****

resource "azurerm_cognitive_account" "qna" {
  name                  = "${var.bot_name}-qna"
  location              = var.qnaluis_location
  resource_group_name   = azurerm_resource_group.rg.name
  kind                  = "QnAMaker"
  qna_runtime_endpoint  = "https://${var.bot_name}-qna-${random_string.rnd.id}.azurewebservices.net"

  sku_name = "F0"
}

# ***** KEY VAULT *****

resource "azurerm_key_vault" "kv" {
  name                  = "${var.bot_name}-kv"
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  tenant_id             = var.tenant_id

  sku_name              = "standard"

  access_policy {
      tenant_id = var.tenant_id
      object_id = data.azurerm_client_config.current.object_id
      secret_permissions = [ "backup", "delete", "get", "list", "purge", "recover", "restore", "set" ] 
  }
  access_policy {
      tenant_id = var.tenant_id
      object_id = azuread_service_principal.sp.id
      secret_permissions = [ "backup", "delete", "get", "list", "purge", "recover", "restore", "set" ] 
  }
  access_policy {
      tenant_id = var.tenant_id
      object_id = data.azuread_service_principal.as_principal.id
      secret_permissions = [ "get", "list" ] 
  }
}

# ***** KEY VAULT SECRETS *****

resource "azurerm_key_vault_secret" "appid" {
  name         = "MicrosoftAppId"
  value        = azuread_application.app.application_id
  key_vault_id = azurerm_key_vault.kv.id
}
resource "azurerm_key_vault_secret" "apppwd" {
  name         = "MicrosoftAppPassword"
  value        = azuread_service_principal_password.spp.value
  key_vault_id = azurerm_key_vault.kv.id
}
resource "azurerm_key_vault_secret" "translator" {
  name         = "BotTranslate--SubscriptionKey"
  value        = azurerm_cognitive_account.tran.primary_access_key
  key_vault_id = azurerm_key_vault.kv.id
}
resource "azurerm_key_vault_secret" "luiskey" {
  name         = "Luis--SubscriptionKey"
  value        = azurerm_cognitive_account.luis.primary_access_key
  key_vault_id = azurerm_key_vault.kv.id
}
resource "azurerm_key_vault_secret" "luisendpoint" {
  name         = "Luis--Endpoint"
  value        = azurerm_cognitive_account.luis.endpoint
  key_vault_id = azurerm_key_vault.kv.id
}
resource "azurerm_key_vault_secret" "qnakey" {
  name         = "QnA--SubscriptionKey"
  value        = azurerm_cognitive_account.qna.primary_access_key
  key_vault_id = azurerm_key_vault.kv.id
}
resource "azurerm_key_vault_secret" "qnaendpoint" {
  name         = "QnA--Endpoint"
  value        = "${azurerm_cognitive_account.qna.endpoint}/qnamaker"
  key_vault_id = azurerm_key_vault.kv.id
}